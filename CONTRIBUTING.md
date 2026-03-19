# Contributing to open-af

Thanks for contributing.

## Development setup

1. Install dependencies:
   ```bash
   npm install
   ```
2. Copy local environment template:
   ```bash
   cp .env.example .env
   ```
3. Authenticate Salesforce CLI and set a default org:
   ```bash
   sf org login web --set-default
   ```

## Validation before PR

Run:

```bash
npm run lint
npm run test:lwc
```

If you touched Apex/runtime behavior, also run org tests:

```bash
npm run test:unit
```

## Security expectations

- Never commit real secrets, access tokens, or org credentials.
- Keep runtime secrets in managed stores (Salesforce secret storage, deployment platform env vars).
- If you suspect an exposure, open a private report via `SECURITY.md`.

## Pull requests

- Keep PRs focused and small.
- Include a short test plan in the PR description.
- Update docs when behavior/setup changes.
