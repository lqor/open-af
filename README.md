# open-af

`open-af` is a sandbox-first Salesforce agent harness packaged as an unlocked package.

## What ships in v1

- Minimal Lightning app with chat, config, and scheduled-task tabs
- Apex agent loop with provider adapters for Anthropic and OpenAI
- Code-registered tool registry for Salesforce data and admin-read operations
- Package-owned records for conversations, runs, tool executions, schedules, and agent config

## Prerequisites

- Node.js 20+
- Salesforce CLI (`sf`)
- A Salesforce org for development/testing

## Quick start

```bash
npm install
cp .env.example .env
sf org login web --set-default
sf project deploy start
```

After deploy/install, assign permissions:

```bash
sf org assign permset -o <org-alias> -n Open_AF_Admin
```

## Secrets and configuration

- Never commit real credentials.
- `.env` is local-only and gitignored.
- `ProviderSecrets` in git must contain placeholders only.
- Put production/runtime credentials in managed secret stores (Salesforce/deployment platform), not in source control.

See [`SECURITY.md`](./SECURITY.md) for reporting and handling expectations.

## Testing

```bash
npm run lint
npm run test:lwc
```

Org-level tests (requires authenticated org):

```bash
npm run test:unit
```

Visual tests live under `tests/visual/` and require Playwright + Salesforce credentials.

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) and [`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md).

## License

MIT — see [`LICENSE`](./LICENSE).
