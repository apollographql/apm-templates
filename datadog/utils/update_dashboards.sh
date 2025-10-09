#!/bin/bash

# Datadog Dashboard Updater Script
# This script fetches dashboard JSON from Datadog API and updates local files

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

# Dashboard mapping: filename:dashboard_id pairs
DASHBOARD_MAPPINGS=(
    "../graphos-template.json:aiz-4aa-wgr"
)

fetch_dashboard() {
    local filename="$1"
    local dashboard_id="$2"
    
    echo -e "${YELLOW}Fetching dashboard ${dashboard_id} for ${filename}...${NC}"
    
    # Make API request
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -H "DD-API-KEY: ${DD_API_KEY}" \
        -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" \
        -H "Content-Type: application/json" \
        "${DD_API_BASE}/dashboard/${dashboard_id}")
    
    # Extract HTTP status code (last line) and JSON response (all lines except last)
    # This approach works on both macOS and Linux
    local http_code
    local json_response
    local temp_file
    temp_file=$(mktemp)
    
    echo "$response" > "$temp_file"
    http_code=$(tail -n1 "$temp_file")
    json_response=$(sed '$d' "$temp_file")
    
    rm -f "$temp_file"

    local tracking_pixel='
        {
            "id": 647653130200787,
            "definition": {
                "type": "image",
                "url": "https://storage.googleapis.com/apollo-apm-templates-pageload-assets/1x1.png",
                "url_dark_theme": "https://storage.googleapis.com/apollo-apm-templates-pageload-assets/1x1.png",
                "sizing": "none",
                "has_background": true,
                "has_border": false,
                "vertical_align": "center",
                "horizontal_align": "center"
            },
            "layout": {
                "x": 11,
                "y": 0,
                "width": 1,
                "height": 1
            }
        }'
    
    if [[ "$http_code" -eq 200 ]]; then
        # Extract only the fields that match browser export format
        echo "$json_response" | jq "{
            title: .title,
            description: .description,
            widgets: .widgets,
            template_variables: .template_variables,
            layout_type: .layout_type,
            notify_list: .notify_list,
            reflow_type: .reflow_type
        } | .widgets += [$tracking_pixel]" > "$filename"
        echo -e "${GREEN}✓ Successfully updated ${filename}${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to fetch dashboard ${dashboard_id} (HTTP ${http_code})${NC}"
        echo "Response: $json_response"
        return 1
    fi
}

main() {
    echo -e "${GREEN}Starting Datadog Dashboard Update...${NC}"
    
    # Track success/failure
    local success_count=0
    local total_count=${#DASHBOARD_MAPPINGS[@]}
    
    echo -e "${YELLOW}Found ${total_count} dashboards to update${NC}"
    
    # Fetch each dashboard
    for mapping in "${DASHBOARD_MAPPINGS[@]}"; do
        # Split the mapping on the colon
        local filename="${mapping%:*}"
        local dashboard_id="${mapping#*:}"
        
        if [[ -z "$filename" || -z "$dashboard_id" ]]; then
            echo -e "${RED}✗ Invalid mapping: ${mapping}${NC}"
            continue
        fi
        
        echo -e "${YELLOW}Processing: ${filename} -> ${dashboard_id}${NC}"
        
        if fetch_dashboard "$filename" "$dashboard_id"; then
            ((success_count++))
        fi
        
        # Small delay to avoid rate limiting
        sleep 0.5
    done

    echo
    echo -e "${GREEN}Update complete: ${success_count}/${total_count} dashboards updated successfully${NC}"

    if [[ $success_count -eq $total_count ]]; then
        echo -e "${GREEN}All dashboards updated successfully!${NC}"
        exit 0
    else
        echo -e "${RED}Some dashboards failed to update. Check the output above for details.${NC}"
        exit 1
    fi
}

show_help() {
    cat << EOF
Datadog Dashboard Updater Script

This script fetches dashboard JSON from Datadog API and updates local files.

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
