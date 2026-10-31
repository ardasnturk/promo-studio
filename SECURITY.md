# Security policy

Promo Studio runs Claude Code on your source code, holds Instagram tokens and
serves a local control API, so security reports are taken seriously and
handled first.

## Reporting a vulnerability

**Please do not open a public issue.** Report it privately through
[GitHub Security Advisories](https://github.com/ardasnturk/promo-studio/security/advisories/new)
(Security → Report a vulnerability). Include:

* what an attacker can do and under which conditions (local user, another app,
  a malicious project folder or template library, …),
* steps to reproduce or a proof of concept,
* the Promo Studio and macOS versions.

You will get an answer within 7 days. Fixes for confirmed issues are released
as soon as possible, and you are credited in the release notes unless you
prefer otherwise.

## Supported versions

| Version | Supported |
|---|---|
| 1.0.x | ✅ |

## Scope

In scope: the local control API (`127.0.0.1`, bearer token in
`~/Library/Application Support/Promo Studio/control.json`), storage of tokens
and keys in the Keychain, the tools Claude Code is allowed to use, rendering
untrusted template libraries, the Instagram OAuth flow and the updater
(SHA-256 and code-signature checks).

Out of scope: vulnerabilities in Claude Code, Remotion, Node.js, Gemini or the
Instagram APIs themselves (report those to their vendors), and attacks that
need an already compromised user account on the Mac.
