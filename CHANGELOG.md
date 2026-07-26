# Changelog

## 1.6.0

### Added

- Safe project bootstrap, profiles, declarative model routing, configuration inspection, and doctor diagnostics.

### Changed

- Bootstrap detects conflicts, skips identical files, and prepares atomic writes before finalization.

### Security

- Configuration is parsed as data; init and doctor do not download, execute models, or repair projects.

### Testing

- CI covers bootstrap, profiles, models, configuration, doctor, and existing integration suites.
