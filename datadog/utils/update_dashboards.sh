#!/bin/bash

# Datadog Dashboard Updater Script
# This script fetches dashboard JSON from Datadog API and updates local files

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to load environment variables from .env file
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
    echo "  1. Creating a .env file (copy ../../.env.example to ../../.env and fill in values)"
    echo "  2. Setting environment variables:"
    echo "     export DD_API_KEY=your_api_key"
    echo "     export DD_APP_KEY=your_app_key"
    echo "  3. Passing them inline when running the script"
    exit 1
fi

# Datadog API base URL
DD_API_BASE="https://api.datadoghq.com/api/v1"

# Dashboard mapping: filename:dashboard_id pairs
DASHBOARD_MAPPINGS=(
    "../cache-metrics.json:air-k6h-j5s"
    "../request-metrics.json:rqe-it2-pcw"
    "../subgraph-request-metrics.json:68y-wn4-f3e"
    "../container-host-metrics.json:3wf-es2-cse"
    "../query-planning.json:s3k-q4m-tnt"
    "../coprocessor-metrics.json:p6f-fc6-pe8"
    "../sentinel-metrics.json:5a4-7pv-hiq"
    "../resource-estimator.json:vyy-vkr-777"
)

# Function to fetch dashboard JSON
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
    
    # Check if request was successful
    if [[ "$http_code" -eq 200 ]]; then
        # Extract only the fields that match browser export format
        echo "$json_response" | jq '{
            title: .title,
            description: .description,
            widgets: .widgets,
            template_variables: .template_variables,
            layout_type: .layout_type,
            notify_list: .notify_list,
            reflow_type: .reflow_type
        }' > "$filename"
        echo -e "${GREEN}✓ Successfully updated ${filename}${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to fetch dashboard ${dashboard_id} (HTTP ${http_code})${NC}"
        echo "Response: $json_response"
        return 1
    fi
}

# Function to check if jq is installed
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is required but not installed${NC}"
        echo "Please install jq:"
        echo "  On macOS: brew install jq"
        echo "  On Ubuntu/Debian: sudo apt-get install jq"
        echo "  On CentOS/RHEL: sudo yum install jq"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}Error: curl is required but not installed${NC}"
        exit 1
    fi
}

# Function to create datadog directory if it doesn't exist
ensure_datadog_dir() {
    # We're already in the datadog directory, so this function is no longer needed
    # but keeping it for compatibility
    :
}

# Main execution
main() {
    echo -e "${GREEN}Starting Datadog Dashboard Update...${NC}"
    
    # Check dependencies
    check_dependencies
    
    # Ensure datadog directory exists
    ensure_datadog_dir
    
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

# Help function
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
  1. Using .env file (recommended):
     cp ../../.env.example ../../.env
     # Edit ../../.env with your actual API keys
     $0

  2. Using environment variables:
     export DD_API_KEY=your_api_key
     export DD_APP_KEY=your_app_key
     $0

  3. Using inline variables:
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
