#!/bin/bash

# Datadog Dashboard Uploader Script
# This script reads local dashboard JSON files and uploads them to Datadog

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

load_env_file() {
    local env_file="./.env"

    if [[ -f "$env_file" ]]; then
        echo -e "${YELLOW}Loading environment variables from ${env_file}...${NC}"
        
        # Load .env file, ignoring comments and empty lines
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip comments and empty lines
            [[ $line =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            # Export the variable
            if [[ $line =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
                export "${BASH_REMATCH[1]}"="${BASH_REMATCH[2]}"
            fi
        done < "$env_file"
    else
        echo -e "${YELLOW}No .env file found. Using environment variables or command line...${NC}"
    fi
}

# Load environment variables from .env file if it exists
load_env_file

# Check if required environment variables are set
if [[ -z "${DD_API_KEY:-}" || -z "${DD_APP_KEY:-}" ]]; then
    echo -e "${RED}Error: DD_API_KEY and DD_APP_KEY must be set${NC}"
    echo "You can set them by:"
    echo "  1. Using direnv with a .envrc file (copy .envrc.example to .envrc and fill in functions)"
    echo "  2. Creating a .env file (copy .env.example to .env and fill in values)"
    echo "  3. Setting environment variables:"
    echo "     export DD_API_KEY=your_api_key"
    echo "     export DD_APP_KEY=your_app_key"
    echo "  4. Passing them inline when running the script"
    exit 1
fi

# Datadog API base URL
DD_API_BASE="https://api.datadoghq.com/api/v1"

# Dashboard mappings: filename:dashboard_id 
# If you want to test dashboard changes without overwriting the live dashboard, comment out the id
# mapping and uncomment the line with no identifier. A new dashboard will be created owned by you
# upon running the script.
DASHBOARD_MAPPINGS=(
    "../graphos-template.json:aiz-4aa-wgr"
   #"../graphos-template.json"
)

upload_dashboard() {
    local filename="$1"
    local dashboard_id="$2"

    if [[ -z "$dashboard_id" ]]; then
        echo -e "${YELLOW}Creating new dashboard from ${filename}...${NC}"
    else
        echo -e "${YELLOW}Updating existing dashboard ${dashboard_id} from ${filename}...${NC}"
    fi

    if [[ ! -f "$filename" ]]; then
        echo -e "${RED}✗ File not found: $filename${NC}"
        return 1
    fi

    local json_payload
    json_payload=$(cat "$filename")

    local http_code
    local response
    local method
    local url

    if [[ -n "$dashboard_id" && "$dashboard_id" != "null" ]]; then
        # Update existing dashboard
        method="PUT"
        url="${DD_API_BASE}/dashboard/${dashboard_id}"
    else
        # Create new dashboard
        method="POST"
        url="${DD_API_BASE}/dashboard"
    fi

    response=$(curl -s -w "\n%{http_code}" \
        -X "$method" \
        -H "DD-API-KEY: ${DD_API_KEY}" \
        -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" \
        -H "Content-Type: application/json" \
        -d "$json_payload" \
        "$url")

    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | sed '$d')

    if [[ "$http_code" =~ ^2 ]]; then
        echo -e "${GREEN}✓ Successfully uploaded ${filename}${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to upload ${filename} (HTTP ${http_code})${NC}"
        echo "Response: $response_body"
        return 1
    fi
}

main() {
    echo -e "${GREEN}Starting Datadog Dashboard Upload...${NC}"
    local success_count=0
    local total_count=${#DASHBOARD_MAPPINGS[@]}

    # Upload each dashboard
    for mapping in "${DASHBOARD_MAPPINGS[@]}"; do
        # Split the mapping on the colon
        local filename="${mapping%:*}"
        local dashboard_id="${mapping#*:}"

        if [[ -z "$filename" ]]; then
            echo -e "${RED}✗ Invalid mapping: ${mapping}${NC}"
            continue
        fi

        # Since Bash's substring extraction will produce the full string with no match
        # this covers the case where no colon was present and therefore we have no ID
        if [[ "$filename" == "$dashboard_id" ]]; then
           dashboard_id=""
        fi

        if [[ -z "$dashboard_id" ]]; then
           echo -e "${YELLOW}Processing: ${filename}${NC}"
        else
           echo -e "${YELLOW}Processing: ${filename} -> ${dashboard_id}${NC}"
        fi

        if upload_dashboard "$filename" "$dashboard_id"; then
            ((success_count++))
        fi

        # Small delay to avoid rate limiting
        sleep 0.5
    done

    echo
    echo -e "${GREEN}Upload complete: ${success_count}/${total_count} dashboards uploaded successfully${NC}"

    if [[ $success_count -eq $total_count ]]; then
        echo -e "${GREEN}All dashboards uploaded successfully!${NC}"
        exit 0
    else
        echo -e "${RED}Some dashboards failed to upload. Check the output above for details.${NC}"
        exit 1
    fi
}

show_help() {
    cat << EOF
Datadog Dashboard Uploader Script

Uploads local dashboard JSON files to Datadog. If the dashboard includes an 'id', it will be updated. Otherwise, a new dashboard will be created.

Usage: $0 [OPTIONS]

Options:
  -h, --help    Show this help message

Environment Variables:
  DD_API_KEY    Your Datadog API key (required)
  DD_APP_KEY    Your Datadog application key (required)

Setup Methods:
  1. Using direnv (recommended):
     cp .envrc.example .envrc
     # Edit .envrc with functions that export your actual API keys
     $0

  2. Using .env:
     cp .env.example .env
     # Edit .env with your actual API keys
     $0

  3. Using environment variables:
     export DD_API_KEY=your_api_key
     export DD_APP_KEY=your_app_key
     $0

  4. Using inline variables:
     DD_API_KEY=your_api_key DD_APP_KEY=your_app_key $0

EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
