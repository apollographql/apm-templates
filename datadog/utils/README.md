## Datadog Dashboard Automation

### Overview

The `update_dashboards.sh` script automates the process of fetching and updating Datadog dashboard
configurations from the Datadog API. This script ensures your local dashboard JSON files stay
synchronized with the current state of dashboards in your Datadog account.

The `destructive_upload_dashboards.sh` script destructively overwrites the current Dashboard
template with the contents of this repository. This should only be used in cases where this
repository's content has deliberately been moved *ahead* of the template in Datadog. For example,
after running the spell-check task in this repository, it may be desirable to upload those changes
rather than manually going and editing its findings in Datadog.

### Setup

#### Using Direnv and a Password/Secrets Manager

1. **Copy the environment template**:

   ```bash
   cp ./.envrc.example ./.envrc
   ```

1. **Configure your API credentials**:

   Edit `./.envrc` and add your Datadog API credentials:
   ```bash
   # Your Datadog API Key
   export DD_API_KEY=$(function_to_retrieve_your_API_key_from_your_secrets_manager)

   # Your Datadog Application Key
   export DD_APP_KEY=$(function_to_retrieve_your_app_key_from_your_secrets_manager)
   ```

   Get your API key from: https://app.datadoghq.com/organization-settings/api-keys

   Get your Application Key from: https://app.datadoghq.com/organization-settings/application-keys

#### Manually

1. **Copy the environment template**:

   ```bash
   cp .env.example .env
   ```

1. **Configure your API credentials**:

   Edit `.env` and add your Datadog API credentials:
   ```bash
   # Your Datadog API Key
   DD_API_KEY=your_actual_api_key

   # Your Datadog Application Key
   DD_APP_KEY=your_actual_app_key
   ```

   Get your API key from: https://app.datadoghq.com/organization-settings/api-keys

   Get your Application Key from: https://app.datadoghq.com/organization-settings/application-keys

### Usage

Run the script to update all dashboard files in this repository from the existing dashboard:

```bash
./update_dashboards.sh
```

If you have made local changes via linting tools after syncing, upload those new changes:

```bash
./destructive_upload_dashboards.sh
```
