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
# 2. Fetch the diff
# ---------------------------------------------------------------------------
DIFF=$(gh api \
  -H "Accept: application/vnd.github.diff" \
  "repos/$REPO/compare/${OLD_TAG}...${NEW_TAG}" \
  2>/dev/null || true)

if [ -z "$DIFF" ]; then
  echo "::warning::Could not fetch diff. Using fallback release notes."
  DIFF="(diff unavailable)"
fi

# Truncate to ~100 KB to stay within model context limits
MAX_DIFF_BYTES=102400
DIFF_BYTES=${#DIFF}
if (( DIFF_BYTES > MAX_DIFF_BYTES )); then
  echo "::notice::Diff is ${DIFF_BYTES} bytes; truncating to ${MAX_DIFF_BYTES} bytes."
  DIFF="${DIFF:0:$MAX_DIFF_BYTES}
... (diff truncated)"
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
  - \"pr_title\": a concise title (no version prefix, no square brackets)
  - \"pr_body\": a single paragraph describing what changed and why

Example response:
{
  \"highlights\": \"- Added X\\n- Fixed Y\",
  \"pr_title\": \"User metrics, expanded type labels, legacy metric removal\",
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
fi

printf '%s\n' "$HIGHLIGHTS" > "$NOTES_DIR/HIGHLIGHTS.md"
printf '%s\n\n%s\n' "$PR_TITLE" "$PR_BODY" > "$NOTES_DIR/PR.md"

echo "Release notes written to $NOTES_DIR/"
echo "  PR title  : $PR_TITLE"
echo "  Highlights: $(echo "$HIGHLIGHTS" | wc -l) lines"
