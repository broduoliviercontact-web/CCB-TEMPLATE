# Project skills

CCB 1.6.1 adds declarative `.ccb/skills.conf`. Ponytail is the first supported skill: it is enabled by default in `full` mode, but no plugin is installed and no network access occurs.

Modes are case-sensitive: `off`, `lite`, `full`, and `ultra`. `off` disables Ponytail rules; `lite` favors necessary, small changes; `full` adds flow tracing, root-cause fixes, and a focused check; `ultra` adds scrutiny for every feature, abstraction, dependency, and extra file. Safety, validation, accessibility, real-time, and hardware constraints remain required in every mode.

`./scripts/ccb.sh skills TARGET` reads the configuration and explains optional agent-specific installation steps without executing them. `config` and `doctor` parse the file as data. Existing 1.6.0 projects are not migrated automatically.
