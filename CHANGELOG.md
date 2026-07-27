# Changelog

## 1.7.0

### Added

- Declarative `.ccb/agents.conf`, agent roles, and read-only agent inspection commands.
- Declarative `.ccb/workflows.conf` and read-only workflow inspection and planning commands.
- Local persistent workflow-run snapshots created on demand with `workflow start`.
- Explicit `workflow resume` and transactional `workflow complete-step` progression, including `--latest` selection and literal context transfer.
- Read-only workflow-run summaries in Config and state, transmission, and residue diagnostics in Doctor.

### Security

- Agent access is declarative only: no agent is launched and no filesystem sandbox is claimed.
- Step results are bounded, parsed as data, and never executed; multi-file publication uses confined backups and logical rollback.

### Testing

- Integration coverage includes state progression, anti-injection, all transaction fail points, byte-identical rollback, Config summaries, and strict Doctor diagnostics.

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
