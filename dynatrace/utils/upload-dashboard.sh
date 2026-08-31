#!/usr/bin/env bash
# Upload a Dynatrace dashboard JSON file.
#
# Classic API mode (default):
#   Requires: DYNATRACE_URL, DYNATRACE_API_TOKEN (WriteConfig scope)
#   Usage: ./upload-dashboard.sh ../dashboard-template.json
#
# Grail (Document API) mode:
#   Requires: DYNATRACE_ENV_ID, DYNATRACE_OAUTH_CLIENT_ID, DYNATRACE_OAUTH_CLIENT_SECRET
#   Usage: ./upload-dashboard.sh ../dashboard-template-grail.json --grail
#
# Variables can be set in a .env file in this directory (see .env.example).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
DASHBOARD_FILE="${1:-}"
MODE="classic"

for arg in "$@"; do
  if [[ "$arg" == "--grail" ]]; then
    MODE="grail"
  fi
done

if [[ -z "$DASHBOARD_FILE" ]]; then
  echo "Usage: $0 <path-to-dashboard.json> [--grail]" >&2
  echo "  Classic: $0 ../dashboard-template.json" >&2
  echo "  Grail:   $0 ../dashboard-template-grail.json --grail" >&2
  exit 1
fi

if [[ ! -f "$DASHBOARD_FILE" ]]; then
  echo "File not found: $DASHBOARD_FILE" >&2
  exit 1
fi

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

# ── Classic API ──────────────────────────────────────────────────────────────
if [[ "$MODE" == "classic" ]]; then
  if [[ -z "${DYNATRACE_URL:-}" ]] || [[ -z "${DYNATRACE_API_TOKEN:-}" ]]; then
    echo "Classic mode requires DYNATRACE_URL and DYNATRACE_API_TOKEN (e.g. in ${ENV_FILE})." >&2
    exit 1
  fi

  BASE_URL="${DYNATRACE_URL%/}"
  ENDPOINT="${BASE_URL}/api/config/v1/dashboards"

  echo "Uploading $(basename "$DASHBOARD_FILE") to ${ENDPOINT} ..."
  HTTP=$(curl -s -w "%{http_code}" -o /tmp/dynatrace-dashboard-response.json \
    -X POST "${ENDPOINT}" \
    -H "Authorization: Api-Token ${DYNATRACE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d @"${DASHBOARD_FILE}")

  if [[ "$HTTP" == "201" ]]; then
    echo "Dashboard created."
    cat /tmp/dynatrace-dashboard-response.json
  else
    echo "Request failed with HTTP ${HTTP}." >&2
    cat /tmp/dynatrace-dashboard-response.json >&2
    exit 1
  fi
fi

# ── Grail Document API ───────────────────────────────────────────────────────
if [[ "$MODE" == "grail" ]]; then
  if [[ -z "${DYNATRACE_ENV_ID:-}" ]] || [[ -z "${DYNATRACE_OAUTH_CLIENT_ID:-}" ]] || [[ -z "${DYNATRACE_OAUTH_CLIENT_SECRET:-}" ]]; then
    echo "Grail mode requires DYNATRACE_ENV_ID, DYNATRACE_OAUTH_CLIENT_ID, and DYNATRACE_OAUTH_CLIENT_SECRET (e.g. in ${ENV_FILE})." >&2
    exit 1
  fi

  echo "Fetching OAuth token ..."
  TOKEN_RESPONSE=$(curl -s -X POST "https://sso.dynatrace.com/sso/oauth2/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=${DYNATRACE_OAUTH_CLIENT_ID}&client_secret=${DYNATRACE_OAUTH_CLIENT_SECRET}&scope=document:documents:write")

  ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null)

  if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "Failed to obtain OAuth token." >&2
    echo "$TOKEN_RESPONSE" >&2
    exit 1
  fi

  # Extract dashboard name from the JSON file
  DASHBOARD_NAME=$(python3 -c "
import sys, json
with open('${DASHBOARD_FILE}') as f:
    d = json.load(f)
# Grail format has no top-level name; fall back to filename
print('$(basename "${DASHBOARD_FILE}" .json)')
" 2>/dev/null || basename "${DASHBOARD_FILE}" .json)

  # Build the Document API payload: name + type + content (stringified JSON)
  PAYLOAD=$(python3 -c "
import json, sys
with open('${DASHBOARD_FILE}') as f:
    content = f.read()
# Validate it parses
json.loads(content)
payload = {
    'name': '${DASHBOARD_NAME}',
    'type': 'dashboard',
    'content': content
}
print(json.dumps(payload))
")

  ENDPOINT="https://${DYNATRACE_ENV_ID}.apps.dynatrace.com/platform/document/v1/documents"
  echo "Uploading $(basename "$DASHBOARD_FILE") to ${ENDPOINT} ..."

  HTTP=$(curl -s -w "%{http_code}" -o /tmp/dynatrace-dashboard-response.json \
    -X POST "${ENDPOINT}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

  if [[ "$HTTP" == "200" ]] || [[ "$HTTP" == "201" ]]; then
    echo "Dashboard created."
    cat /tmp/dynatrace-dashboard-response.json
  else
    echo "Request failed with HTTP ${HTTP}." >&2
    cat /tmp/dynatrace-dashboard-response.json >&2
    exit 1
  fi
fi
