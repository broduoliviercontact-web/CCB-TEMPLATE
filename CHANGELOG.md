# Changelog

## 1.6.1

### Added

- Declarative project skills, Ponytail modes, and read-only `ccb skills` guidance.

### Changed

- Bootstrap manages `skills.conf` alongside project, model, context, and agent guidance.

### Security

- Ponytail plugins and hooks are never installed or activated automatically.

### Testing

- CI covers skills configuration and instructions.

## 1.6.0

### Added

- Safe project bootstrap, profiles, declarative model routing, configuration inspection, and doctor diagnostics.

### Changed

- Bootstrap detects conflicts, skips identical files, and prepares atomic writes before finalization.

### Security

- Configuration is parsed as data; init and doctor do not download, execute models, or repair projects.

### Testing

- CI covers bootstrap, profiles, models, configuration, doctor, and existing integration suites.
