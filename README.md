# open-af

`open-af` is a sandbox-first Salesforce agent harness packaged as an unlocked package.

## What ships in v1

- A minimal Lightning app with chat, config, and scheduled-task tabs
- An Apex agent loop with provider adapters for Anthropic and OpenAI
- A code-registered tool registry for Salesforce data and admin-read operations
- Package-owned records for conversations, runs, tool executions, schedules, and agent config

## Local project

This repo is a standard Salesforce DX project.

## Post-install

After deploying or installing into an org, assign the `Open_AF_Admin` permission set to users who should see the app tabs and access the package runtime.

```bash
sf org assign permset -o <org-alias> -n Open_AF_Admin
```

### Useful commands

```bash
npm install
cp .env.example .env
sf org login web --set-default
sf project deploy start
sf package version create --package open-af --installation-key-bypass --wait 20
```

## v1 key limitations

- Secrets should live only in a local `.env` file; `ProviderSecrets` in git contains placeholders and must be replaced through your org-specific secret setup before runtime
- Runtime executes in system context
- The base package does not modify Apex, LWC, or metadata
- The UI uses polling rather than streaming
