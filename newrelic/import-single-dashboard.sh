#!/bin/bash

# Import a single Apollo Router Dashboard to New Relic
# Usage: NEW_RELIC_USER_API_KEY=your-key NEW_RELIC_ACCOUNT_ID=123456 ./import-single-dashboard.sh <dashboard-file>

if [ $# -eq 0 ]; then
    echo "Usage: NEW_RELIC_USER_API_KEY=your-key NEW_RELIC_ACCOUNT_ID=123456 $0 <dashboard-file>"
    echo "Example: NEW_RELIC_USER_API_KEY=your-key NEW_RELIC_ACCOUNT_ID=123456 $0 example-dashboard.json"
    exit 1
fi

DASHBOARD_FILE=$1
USER_API_KEY="${NEW_RELIC_USER_API_KEY}"
ACCOUNT_ID="${NEW_RELIC_ACCOUNT_ID}"

# Validate required environment variables
if [ -z "$USER_API_KEY" ]; then
    echo "Error: NEW_RELIC_USER_API_KEY environment variable not set"
    exit 1
fi

if [ -z "$ACCOUNT_ID" ]; then
    echo "Error: NEW_RELIC_ACCOUNT_ID environment variable not set"
    exit 1
fi

if [ ! -f "$DASHBOARD_FILE" ]; then
    echo "Error: File $DASHBOARD_FILE not found!"
    exit 1
fi

echo "Importing dashboard from: $DASHBOARD_FILE"
echo "Account ID: $ACCOUNT_ID"
echo ""

# New Relic dashboard import uses the NerdGraph API with dashboardCreate mutation
# The dashboard JSON needs to be embedded in the mutation

MUTATION=$(jq -n \
    --arg accountId "$ACCOUNT_ID" \
    --slurpfile dashboard "$DASHBOARD_FILE" \
    '{
        query: "mutation CreateDashboard($accountId: Int!, $dashboard: DashboardInput!) { dashboardCreate(accountId: $accountId, dashboard: $dashboard) { entityResult { guid name } errors { description type } } }",
        variables: {
            accountId: ($accountId | tonumber),
            dashboard: $dashboard[0]
        }
    }')

# Execute the API call
echo "Calling New Relic API..."
RESPONSE=$(curl -s -X POST https://api.newrelic.com/graphql \
    -H "Content-Type: application/json" \
    -H "API-Key: $USER_API_KEY" \
    -d "$MUTATION")

# Check for errors
if echo "$RESPONSE" | jq -e '.errors' > /dev/null 2>&1; then
    echo "❌ API Error:"
    echo "$RESPONSE" | jq '.errors'
    exit 1
fi

if echo "$RESPONSE" | jq -e '.data.dashboardCreate.errors | length > 0' > /dev/null 2>&1; then
    echo "❌ Dashboard Creation Error:"
    echo "$RESPONSE" | jq '.data.dashboardCreate.errors'
    exit 1
fi

# Success!
GUID=$(echo "$RESPONSE" | jq -r '.data.dashboardCreate.entityResult.guid')
NAME=$(echo "$RESPONSE" | jq -r '.data.dashboardCreate.entityResult.name')

echo "✅ Dashboard imported successfully!"
echo "   Name: $NAME"
echo "   GUID: $GUID"
echo ""
echo "View your dashboard at:"
echo "https://one.newrelic.com/dashboards/$GUID"
