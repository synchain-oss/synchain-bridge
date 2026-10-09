# Contributing to Synchain Bridge

Thanks for your interest in contributing. Synchain Bridge is the open-source **plugin side** of the Synchain platform: a JUCE 8 + WebView2 VST3 / AU / AAX plugin that streams DAW audio to remote collaborators over a local WebSocket. The receiving side is the closed-source Synchain web application (SaaS).

## 0. Language policy

- Issues and pull requests may be written in **Chinese or English**; maintainers reply in the language you used.
- Internal maintainer communication is in Chinese.
- The frozen contract (`BRIDGE_CONTRACT.md`) is the single source of truth; where a Chinese and English wording differ, the contract file as committed is authoritative.

## 1. Code of conduct

All participants are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## 2. Developer Certificate of Origin (DCO)

Every commit must carry a `Signed-off-by:` trailer. Sign with:

```
git commit -s
```

We use the DCO, not a CLA. This is machine-enforced by the `branch-gate` CI check (an inline `gh api` assertion; no third-party action is used, because the org allow-list blocks third-party DCO actions). To fix a commit that is missing the trailer:

```
git commit -s --amend     # last commit
git rebase --signoff      # a range of commits
```

## 3. Branch model

- The default branch is `dev`; the Bridge feature trunk is `feature/extraction` (ADR-013 / J13). AAX (Pro Tools) work lives on the `feature/aax` trunk, with sub-branches named `feat/AAX-NN-slug`. The release branch is `prod` (there is no `stage`).
- Promotion: `feat/*` → (sub-PR) `feature/*` → `dev` → `prod`. `prod` accepts PRs only from this repository's `dev` (enforced by `branch-gate`, for fork and bot PRs too), and release tags `vX.Y.Z` are cut only on `prod`.
- **Internal contributors** work on `feat/<TASKID>-<slug>` branches based on the relevant trunk (`feature/extraction` or `feature/aax`), then open a PR to that trunk. Same-repo PRs to `dev` are only accepted from `feat/*` / `feature/*` (plus `dependabot/*`).
- **External contributors** (J31/J41): fork the repo, use **any branch name** (do not use `dev`, `stage`, `prod`, `feature/v1`, or `feature/extraction`), and open a PR to `dev`. `branch-gate` does not reject fork PRs to `dev`; it only asserts the head branch is not one of those long-lived names. Fork PRs run the secret-free build/tests (after a maintainer approves the run); the AI review bots do not run automatically. A maintainer manually adds the `external` label.

## 4. Commit convention

`type(scope): 描述` — the description may be in Chinese or English. Types: `fix`, `feat`, `docs`, `chore`, `refactor`, `test`, `ci`, `style`, `perf`, `revert`, `harden`.

## 5. Environment setup

See `README.md` (Requirements + Build from source) and the table in `CLAUDE.md` §6. In short: JUCE 8.0.8 (see `.juce-version`), CMake ≥ 3.22, MSVC 2022 with static CRT `/MT`, WebView2 SDK (NuGet) + Evergreen Runtime, pluginval v1.0.4 (see `.pluginval-version`), and `ixwebsocket` (`x64-windows-static`) via vcpkg in manifest mode — pinned by the repo's `vcpkg.json`, installed automatically at configure time. The AAX SDK ships inside JUCE, so there is nothing extra to download; the normal build produces the AAX target too (`-DSYNCHAIN_BRIDGE_AAX=OFF` skips it). External contributors cannot produce a signed AAX (signing needs the maintainer's PACE credentials), and an unsigned build loads only in Pro Tools Developer, which is distributed by Avid to AAX developers. If you cannot test in Pro Tools, say so in the PR; the maintainer runs the Pro Tools checklist in `docs/DAW_TEST_GUIDE.md`.

## 6. Local gates before a PR

Run the same command list documented in `CLAUDE.md` §2 (single source of truth): `pwsh scripts/gates.ps1` (build + pluginval + gitleaks + reuse lint + zero-warning + the port `9420` consistency check). Add `-IncludeAax` to also run the AAX gates (5c bundle structure, 5d packaging smoke test, 5e the optional AAX Validator, which stays SKIP unless `-AaxValidatorPath` is given); gate 3h, which rejects code-signing material and Avid tools in the working tree, always runs. The full strictness-5 run **including the GUI editor** can only be validated locally on a real Windows 11 machine.

## 7. Review process and response time

- Maintainers review PRs and respond within a few working days.
- Address **all** review comments — not only the bot comments (D2).
- Sub-PRs (base = `feature/extraction`) are merged by a human maintainer after review.

## 8. ★ Frozen contract — PRs that will not be accepted

`BRIDGE_CONTRACT.md` is the single source of truth for the wire protocol (bridge #1: editor JS↔C++, and bridge #2: WebSocket). The following changes will be rejected:

- **Protocol changes without a compatibility statement.** The plugin (C++) lives in this repository while the browser client lives in the closed-source Synchain web application — a protocol change can no longer be made atomically across both sides in one PR. Any protocol-change PR must state how old clients behave with new plugins and vice versa (new-version ↔ old-version interoperability).
- **Breaking the default port `9420` consistency** across the three in-repo locations: `src/BridgeApi.h` (`DefaultPort`), `web/bridge.js`, and `web-preview/mock-server.mjs`.
- **Changing the manufacturer/plugin codes (`Snch` / `Snb1`), the bundle ID or the AAX identifier (both `com.synchain.bridge`).** These make up the VST3 unique ID, and the codes are also the AAX manufacturer / product IDs; changing them makes DAWs treat the plugin as a brand-new plugin and orphans existing projects.
- **Removing an AAX channel layout.** Each layout accepted under AAX by `isBusesLayoutSupported` (currently mono→mono and stereo→stereo) gets its own AAX plug-in ID that Pro Tools stores in sessions; once released, layouts may only be added, never removed.
- **Violating the real-time thread rules** in `CLAUDE.md` §8 (allocations, locks, I/O, logging, or exceptions inside `processBlock`).

## 9. Release process (maintainers only)

Releases go `feature/*` → `dev` (PR) → `prod` (PR, from `dev` only), and are cut by tagging `vX.Y.Z` on the `prod` merge commit (the version truth is `project(... VERSION)` in `CMakeLists.txt`). The `release.yml` workflow builds, runs pluginval, verifies the tag matches the CMake version, and produces the zip + sha256 draft release. See [`docs/release.md`](docs/release.md) for the full runbook. VST3 / AU are not signed. AAX files are signed by hand by the maintainer on a local machine with `scripts/sign-aax.ps1` / `scripts/sign-aax-macos.sh` (CI holds no signing credentials and only produces `-UNSIGNED` artifacts) and uploaded to the draft release afterwards — see [§7 of `docs/release.md`](docs/release.md#7-aaxpro-tools本机签名--手工上传).
