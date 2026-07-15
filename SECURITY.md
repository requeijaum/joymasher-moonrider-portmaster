# Security policy

## Supported versions

Only the latest commit on `main` and the latest GitHub prerelease receive security fixes. Experimental branches are unsupported.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting feature for this repository. Do not open a public issue for credentials, command injection, unsafe archive extraction, path traversal or other vulnerabilities that could put testers' machines or handhelds at risk.

Include:

- affected commit or release;
- impact and threat model;
- minimal reproduction without proprietary game assets;
- suggested mitigation, if known.

Do not send passwords, access tokens, private keys, commercial assets or unsanitized device backups.

## Release security model

Public release gates reject tracked commercial media, concrete private infrastructure and common secret patterns. Release artifacts are generated from a clean checkout and accompanied by SHA-256 checksums.

This project disables the WebKit sandbox on its tested legacy kernel because the required namespaces are unavailable. Treat the game payload as trusted local content and do not browse arbitrary remote pages through the bundled runtime.
