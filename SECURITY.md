# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| latest minor (x.Y.*) | ✅ |
| older | ❌ |

## Reporting a vulnerability

**Do not open a public issue.** Use GitHub Private Vulnerability Reporting: Security → Report a vulnerability.

Alternative contact (backup channel): **contact@synchain.ca**.

## Response targets

- First response: within 3 working days
- Fix or mitigation: 14 days for high severity, 30 days for medium severity
- Disclosure: a public advisory (GHSA) is published 7 days after the fix ships

## Scope

- ✅ Memory-safety issues, out-of-bounds access, or uninitialized reads in this repository's code.
- ✅ Crashes or arbitrary writes caused by parsing the WebSocket protocol (binary PCM frames or JSON text frames) — including the 12-byte header, `numSamples` / `channels` bounds, and interleaved staging.
- ✅ Cross-Site WebSocket Hijacking (CSWSH): bypasses of the `Origin` allow-list in the local bridge server.
- ✅ Supply-chain issues in the build scripts / CI.
- ❌ Upstream issues in JUCE / VST3 SDK / WebView2 Runtime (report those upstream).
- ❌ Audio anomalies caused by the user's own routing changes (a usage question, not a vulnerability).
