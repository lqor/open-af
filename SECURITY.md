# Security Policy

## Supported versions

This project is pre-1.0 and currently supports the latest `main` branch.

## Reporting a vulnerability

Please do **not** open public issues for suspected vulnerabilities.

Instead, report privately to the maintainer (Igor Kudryk) with:
- impact summary
- reproduction steps
- affected files/components
- suggested remediation (if available)

Acknowledgement target: within 72 hours.

## Secret handling rules

- No live credentials in git-tracked files.
- `.env` is local-only and ignored.
- `.env.example` must contain placeholders only.
- If a secret was exposed, rotate it immediately and treat history/CI logs as potentially compromised.
