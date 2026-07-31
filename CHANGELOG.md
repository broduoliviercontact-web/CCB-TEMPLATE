# Changelog

## Unreleased

### Changed

- Keep RTK and Tilth token optimization enabled by default. `--token-optimization` remains accepted
  for explicit scripts, while `--no-token-optimization` and the advanced initializer opt-out remain
  available when needed.
- Keep dependency-free minimal delivery rules in the four generated agent skills, with attribution
  to Ponytail inspiration but no Ponytail plugin dependency.

### Added

- `ccb-template doctor` with `[OK]`, `[WARNING]` and `[MISSING]` states, plus `doctor --full` for
  optional RTK, npx, Tilth and local monitoring checks.
- Simple interactive `ccb-template init` project creation with automatic Cloud model selection,
  one main confirmation and Git repository initialization.
- `ccb-template init --advanced` for per-agent Ollama Cloud model selection and optional
  RTK/Tilth and token-monitoring choices.
- `ccb-template monitor model` to inspect and atomically update installed Ollama Cloud models in a
  generated project's `.ccb/ccb.config`.
- Per-project token-monitor ports with persistent recovery metadata and proxy integration tests.

### Fixed

- Prewarm Tilth in each isolated Claude Code agent home, seed Claude Code onboarding/project-trust
  state and add the expected Claude Code CLI link, avoiding first-start theme/import prompts and
  MCP timeouts when all four CCB agents launch together.
- Align the generated CCB topology with the four permanent roles supported by the current CCB
  governance: manager, graph, developer and reviewer.
- Keep CCB runtime state and Graphify outputs out of the repository worktree.
- Start and health-check the token proxy before CCB, preventing an unavailable proxy from causing
  CCB to remove agent base URLs.

## 2.0.0 — 2026-07-28

### Breaking changes

- Remove the local V1 CCB engine and root `./ccb` wrapper.
- Remove home-grown workflows, runs and direct Ollama calls.
- Every `ccb` command now denotes the official global CCB binary.
- V1 projects are not migrated automatically.

### Added

- Bootstrap for the official CCB and generated `.ccb/ccb.config`.
- Five Claude Code agents connected to Ollama Cloud.
- Dependency preflight, dry-run, and atomic policy and memory installation.
- V2 documentation, clean-tree checks, release checks, and CI coverage.

### Removed

- V1 Control Room, provider router, agent launcher, model presets and project profiles.
- V1 scripts, tests, manuals, caches and duplicate runtime assets.

### Migration

- Back up the former `.ccb` directory before changing a V1 project.
- Follow `docs/v2-migration-from-v1.md` and copy useful information manually.
- Use the `v1.8.0` tag to access the former engine.

## 1.8.0

### Added

- Add the executable `./ccb` wrapper and a transactional zero-friction `quickstart` command.
- Add the stable `coding-cloud` preset and explicit cloud/local preflight reporting.
- Add quickstart, cloud setup, troubleshooting, and acceptance-test documentation.

### Safety and compatibility

- Keep legacy and role-based model configuration formats compatible through the existing parser.
- Preserve local-only Ollama access, no automatic model downloads, no Git changes, and no secret output.
- Keep V1.7.0 and V1.7.1 project metadata and run records valid without migration.

## 1.7.1

### Fixed

- Accept both historical and role-based `.ccb/models.conf` files through one centralized parser.
- Preserve distinct role model assignments in Config, Doctor, model commands, and workflow snapshots.
- Normalize provider result line endings before CCB appends workflow transmission delimiters.

### Compatibility and security

- Keep V1.7.0 model files and runs valid without migration, using the documented planner/coder/default mapping.
- Render only validated non-secret model fields; stored configuration is never evaluated.
- Preserve the 256 KiB response limit, atomic publication, rollback behavior, and literal treatment of model output.

### Testing

- Add explicit regression coverage for both model schemas, normal and strict Doctor, cloud role snapshots, Inspect, newline and no-newline responses, context transmission, and full sequential orchestration.
- Continue covering retries, cancellation, history, transaction rollback, and residue cleanup in the historical suites.

## 1.7.0

- Add bounded sequential `workflow run` automation with persistent checkpoints, safe interruption recovery, a distinct orchestration lock, and no automatic retries.
- Expose automation metadata safely through Status, Inspect, Config, and Doctor while keeping model content opaque.
- Add manual bounded retries, durable cancellation, and deterministic read-only workflow history.

### Added

- Declarative `.ccb/agents.conf`, agent roles, and read-only agent inspection commands.
- Declarative `.ccb/workflows.conf` and read-only workflow inspection and planning commands.
- Local persistent workflow-run snapshots created on demand with `workflow start`.
- Explicit `workflow resume` and transactional `workflow complete-step` progression, including `--latest` selection and literal context transfer.
- Read-only workflow-run summaries in Config and state, transmission, and residue diagnostics in Doctor.
- Controlled single-step execution through local Ollama, with bounded snapshot prompts, atomic pending results, execution metadata, and per-run locking.
- Safe execution summaries in Status, Inspect, and Config, plus Doctor validation for metadata, locks, and temporary residue.
- Explicit `workflow retry-step` with at most three attempts and metadata-only failure archives.
- Transactional `workflow cancel` with preserved checkpoints and immutable execution history.
- Read-only `workflow history` timelines plus D3 reliability and observability counters in Config.

### Security

- Agent access is declarative only: no agent is launched and no filesystem sandbox is claimed.
- Step results are bounded, parsed as data, and never executed; multi-file publication uses confined backups and logical rollback.
- Ollama execution is fixed to loopback, does not follow redirects, and treats context, input, and model output as opaque data.
- Retry and cancellation transactions use confined backups and logical rollback; no retry is automatic and no active orchestration is stopped implicitly.
- History, Config, and Doctor never expose full errors, prompts, responses, Markdown bodies, tokens, or secrets and never repair a run.

### Testing

- Integration coverage includes state progression, anti-injection, all transaction fail points, byte-identical rollback, Config summaries, and strict Doctor diagnostics.
- D3 coverage includes retry limits and archives, cancellation policies, deterministic history, read-only observability, corruption diagnostics, and legacy-run compatibility.

## 1.6.1

### Added

- Declarative project skills, Ponytail modes, and read-only `ccb skills` guidance.
- Explicit `ccb upgrade TARGET` migration from bootstrap project format 1.6.0 to 1.6.1.

### Changed

- Bootstrap manages `skills.conf` alongside project, model, context, and agent guidance.
- Doctor recognizes a 1.6.0 project as upgradeable and recommends, but never performs, the upgrade.

### Security

- Ponytail plugins and hooks are never installed or activated automatically.
- Upgrade refuses customized managed files and uses atomic replacements with rollback attempts.

### Testing

- CI covers skills configuration and instructions.
- CI covers upgrade planning, dry-run, conflicts, and idempotence.

## 1.6.0

### Added

- Safe project bootstrap, profiles, declarative model routing, configuration inspection, and doctor diagnostics.

### Changed

- Bootstrap detects conflicts, skips identical files, and prepares atomic writes before finalization.

### Security

- Configuration is parsed as data; init and doctor do not download, execute models, or repair projects.

### Testing

- CI covers bootstrap, profiles, models, configuration, doctor, and existing integration suites.
