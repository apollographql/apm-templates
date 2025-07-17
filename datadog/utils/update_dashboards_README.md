
## Datadog Dashboard Automation

### Overview

The `update_dashboards.sh` script automates the process of fetching and updating Datadog dashboard configurations from the Datadog API. This script ensures your local dashboard JSON files stay synchronized with the current state of dashboards in your Datadog account.

### Setup

1. **Copy the environment template**:
   ```bash
   cp ../../.env.example ../../.env
   ```

2. **Configure your API credentials**:
   Edit `../../.env` and add your Datadog API credentials:
   ```bash
   # Your Datadog API Key
   DD_API_KEY=your_actual_api_key

   # Your Datadog Application Key  
   DD_APP_KEY=your_actual_app_key
   ```

   Get your API key from: https://app.datadoghq.com/organization-settings/api-keys
   Get your Application Key from: https://app.datadoghq.com/organization-settings/application-keys

3. **Make the script executable**:
   ```bash
   chmod +x update_dashboards.sh
   ```

### Usage

Run the script to update all dashboard files:

```bash
./update_dashboards.sh
```

The script will:
1. Load API credentials from `../../.env`
2. Fetch current configurations for all 8 runtime-readiness dashboards
3. Extract clean JSON (title, description, widgets, template_variables, etc.)
4. Update the corresponding JSON files in the parent directory (`../`)