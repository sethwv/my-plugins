#!/usr/bin/env bash
# generate-release-notes.sh
#
# Calls GitHub Models API (gpt-4o) to generate release notes from the diff
# between the previous and new release tags.
#
# Required env:
#   REPO        - owner/repo (e.g. sethwv/dispatcharr-exporter)
#   TAG         - new release tag (e.g. v3.0.0)
#   VERSION     - version string without leading v (e.g. 3.0.0)
#   RELEASE_URL - HTML URL of the GitHub release
#   SETH_PAT    - GitHub PAT with Models access
#
# Outputs (written to /tmp/release-notes/):
#   HIGHLIGHTS.md  - bullet-point summary for PR body / Discord
#   PR.md          - line 1: title, line 3+: paragraph body

set -euo pipefail

NOTES_DIR="/tmp/release-notes"
mkdir -p "$NOTES_DIR"

# ---------------------------------------------------------------------------
# 1. Find the previous stable release tag
# ---------------------------------------------------------------------------
echo "Fetching release list for $REPO..."

RELEASES=$(gh api "repos/$REPO/releases" --paginate --jq '[.[] | select(.prerelease == false and .draft == false) | .tag_name]')
RELEASE_COUNT=$(echo "$RELEASES" | jq 'length')

NEW_TAG="$TAG"

if [ "$RELEASE_COUNT" -lt 2 ]; then
  # First-ever release - compare against the initial commit
  echo "Only one release found; comparing against initial commit."
  OLD_TAG=$(gh api "repos/$REPO/commits?per_page=1&sha=main" --jq '.[0].sha' 2>/dev/null || \
            gh api "repos/$REPO/commits?per_page=1" --jq '.[0].sha')
  IS_FIRST_RELEASE=true
else
  # Second entry in the sorted list is the previous stable release
  OLD_TAG=$(echo "$RELEASES" | jq -r '.[1]')
  IS_FIRST_RELEASE=false
fi

echo "Comparing $OLD_TAG ... $NEW_TAG"

# ---------------------------------------------------------------------------
# 2. Fetch the diff - smart file prioritisation
# ---------------------------------------------------------------------------
# Get the list of changed files with their patch sizes
COMPARE=$(gh api "repos/$REPO/compare/${OLD_TAG}...${NEW_TAG}" 2>/dev/null || true)

if [ -z "$COMPARE" ]; then
  echo "::warning::Could not fetch compare data. Using fallback release notes."
  DIFF="(diff unavailable)"
else
  # Priority order for files (most signal first):
  #   1. plugin.json / CHANGELOG / README / docs
  #   2. Python source (.py) excluding __init__ and migrations
  #   3. Everything else
  # Files to skip entirely: lock files, generated, binary-like
  SKIP_PATTERN='\.(lock|min\.js|map|png|jpg|gif|svg|ico|woff|ttf|eot)$|package-lock|yarn\.lock|poetry\.lock|__pycache__|\.pyc'

  PRIORITY_FILES=$(echo "$COMPARE" | jq -r '
    .files[]
    | select(.filename | test("'"$SKIP_PATTERN"'") | not)
    | [
        (if (.filename | test("plugin\\.json|CHANGELOG|README|HIGHLIGHTS|METRICS|\\.md$")) then 0
         elif (.filename | test("\\.py$") and (test("__init__|migration") | not)) then 1
         else 2 end),
        .changes,
        .filename,
        (.patch // "")
      ]
    | @json
  ' 2>/dev/null | sort -t$'\t' -k1,1n || true)

  MAX_DIFF_BYTES=14000
  DIFF=""
  INCLUDED=0
  SKIPPED=0

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    FILENAME=$(echo "$line" | jq -r '.[2]')
    PATCH=$(echo "$line"    | jq -r '.[3]')
    [ -z "$PATCH" ] && continue

    FILE_HEADER="diff --git a/$FILENAME b/$FILENAME\n"
    CANDIDATE="${DIFF}${FILE_HEADER}${PATCH}\n"
    if (( ${#CANDIDATE} <= MAX_DIFF_BYTES )); then
      DIFF="$CANDIDATE"
      INCLUDED=$(( INCLUDED + 1 ))
    else
      SKIPPED=$(( SKIPPED + 1 ))
    fi
  done <<< "$PRIORITY_FILES"

  echo "::notice::Diff: $INCLUDED files included, $SKIPPED skipped (budget: ${MAX_DIFF_BYTES} bytes, used: ${#DIFF} bytes)."

  if [ -z "$DIFF" ]; then
    echo "::warning::No diff content available. Using fallback."
    DIFF="(diff unavailable)"
  fi
fi

# ---------------------------------------------------------------------------
# 3. Read and adapt the Changelog agent prompt (strip YAML frontmatter)
# ---------------------------------------------------------------------------
AGENT_PROMPT=$(sed '/^---$/,/^---$/d' .github/scripts/Changelog.agent.md | sed '/^$/{ N; /^\n$/d; }')

SYSTEM_PROMPT="${AGENT_PROMPT}

IMPORTANT - CI OUTPUT FORMAT:
You are running in a CI environment, not an interactive editor. Do NOT create files.
Instead, return a JSON object with exactly these three fields:
  - \"highlights\": bullet-point list (each line starts with \"- \"), user-facing features only
  - \"pr_title\": a short imperative description of the changes (no version prefix, no square brackets, no plugin name)
  - \"pr_body\": a single paragraph describing what changed and why

The commit message subject will be formatted as \"v{VERSION}: {pr_title}\", for example:
  \"v3.0.0: Add user metrics and remove legacy stream labels\"
  \"v1.0.0: Initial release\"
So pr_title should complete that sentence naturally and be under 60 characters.

Example response:
{
  \"highlights\": \"- Added X\\n- Fixed Y\",
  \"pr_title\": \"Add user metrics and remove legacy stream labels\",
  \"pr_body\": \"Adds opt-in user metrics and removes all legacy formats. Minimum Dispatcharr version raised to v0.22.0.\"
}

Do not include any text outside the JSON object."

USER_MESSAGE="Generate release notes for version ${VERSION} of the plugin at ${REPO}.

Diff (${OLD_TAG} to ${NEW_TAG}):

${DIFF}"

# ---------------------------------------------------------------------------
# 4. Call GitHub Models API
# ---------------------------------------------------------------------------
echo "Calling GitHub Models API..."

REQUEST_BODY=$(jq -n \
  --arg system "$SYSTEM_PROMPT" \
  --arg user "$USER_MESSAGE" \
  '{
    model: "gpt-4o",
    messages: [
      {role: "system", content: $system},
      {role: "user",   content: $user}
    ],
    response_format: {type: "json_object"}
  }')

HTTP_STATUS=""
API_RESPONSE=$(curl -s -w "\n__HTTP_STATUS__:%{http_code}" \
  -H "Authorization: Bearer $SETH_PAT" \
  -H "Content-Type: application/json" \
  -d "$REQUEST_BODY" \
  "https://models.inference.ai.azure.com/chat/completions")

# Split status code from body
HTTP_STATUS=$(echo "$API_RESPONSE" | tail -1 | sed 's/__HTTP_STATUS__://')
API_RESPONSE=$(echo "$API_RESPONSE" | sed '$d')

echo "GitHub Models API HTTP status: $HTTP_STATUS"

if [ -z "$API_RESPONSE" ]; then
  echo "::warning::GitHub Models API returned empty response (HTTP $HTTP_STATUS). Using fallback."
elif echo "$API_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
  ERROR_MSG=$(echo "$API_RESPONSE" | jq -r '.error.message // .error // "unknown error"')
  echo "::warning::GitHub Models API error (HTTP $HTTP_STATUS): $ERROR_MSG. Using fallback."
  API_RESPONSE=""
elif [ "$HTTP_STATUS" != "200" ]; then
  echo "::warning::GitHub Models API returned HTTP $HTTP_STATUS. Response: $(echo "$API_RESPONSE" | head -c 500). Using fallback."
  API_RESPONSE=""
fi

# Parse the content field from the chat completion response
CONTENT=$(echo "$API_RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null || true)

if [ -z "$CONTENT" ]; then
  echo "::warning::Could not parse model response. Using fallback release notes."
  cat > "$NOTES_DIR/HIGHLIGHTS.md" <<EOF
- Updated to v${VERSION}
EOF
  cat > "$NOTES_DIR/PR.md" <<EOF
v${VERSION}: Plugin update

Updates plugin to v${VERSION}. See release: ${RELEASE_URL}
EOF
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. Extract fields and write output files
# ---------------------------------------------------------------------------
HIGHLIGHTS=$(echo "$CONTENT" | jq -r '.highlights // empty')
PR_TITLE=$(echo "$CONTENT"   | jq -r '.pr_title   // empty')
PR_BODY=$(echo "$CONTENT"    | jq -r '.pr_body     // empty')

if [ -z "$HIGHLIGHTS" ] || [ -z "$PR_TITLE" ] || [ -z "$PR_BODY" ]; then
  echo "::warning::Model response missing expected fields. Using fallback."
  HIGHLIGHTS="- Updated to v${VERSION}"
  PR_TITLE="v${VERSION}: Plugin update"
  PR_BODY="Updates plugin to v${VERSION}. See release: ${RELEASE_URL}"
else
  PR_TITLE="v${VERSION}: ${PR_TITLE}"
fi

printf '%s\n' "$HIGHLIGHTS" > "$NOTES_DIR/HIGHLIGHTS.md"
printf '%s\n\n%s\n' "$PR_TITLE" "$PR_BODY" > "$NOTES_DIR/PR.md"

echo "Release notes written to $NOTES_DIR/"
echo "  PR title  : $PR_TITLE"
echo "  Highlights: $(echo "$HIGHLIGHTS" | wc -l) lines"
