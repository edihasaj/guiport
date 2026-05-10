# Security Policy

## Reporting a vulnerability

Email **edihasaj@gmail.com** with details. Do not file a public GitHub issue.

Please include:

- A description of the vulnerability.
- Steps to reproduce.
- Affected version/commit.
- Expected vs. observed impact.

You'll get an acknowledgement within 72 hours and a status update within 7 days.

## Threat model

guiport requires Accessibility and Screen Recording permissions to function. With those granted, it can:

- Read the full UI of any running app (AX tree + screenshots).
- Synthesize keyboard and mouse input as the current user.
- Press buttons via `AXPress`.

That power is the point — but it means **only run guiport binaries you trust**. Treat YAML test files like shell scripts: anyone who can write them can drive your machine.

## Hardening tips

- Run replay tests against scratch user accounts or VMs when possible.
- Don't store secrets in YAML test files.
- Review recordings before committing — `record` may capture typed text including passwords.
- Use App-Sandbox-blocking allowlists for which apps guiport may operate (planned).

## Supported versions

Pre-1.0 only the latest minor receives fixes.
