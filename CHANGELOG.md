# Changelog

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
