# Security Policy

## Supported versions

Security fixes are prioritized for the latest release and the default branch. Older
releases may receive fixes where practical.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/remyhuang03/remya-bar/security/advisories/new).
Keep vulnerability details out of issues and pull requests. Include the affected version
or commit, environment, expected security boundary, observed impact, and sanitized
evidence. Remove credentials, private data, and sensitive logs.

Coordinate disclosure with the maintainer so they can verify the report and prepare a
fix.

## Scope

Remy'a Bar handles notifications, tray and media data, Hyprland IPC and sidebar actions.
Report unauthorized disclosure of desktop data, actions triggered outside the user's
request, and boundary violations involving input injection or compositor integration.

Report standalone dependency vulnerabilities to the upstream project. Report exposure
specific to this application's integration here.
