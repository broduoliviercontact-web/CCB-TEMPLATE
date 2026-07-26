# Safe project upgrade

CCB 1.6.1 can safely migrate a bootstrap project created by 1.6.0:

```sh
./scripts/ccb.sh upgrade /path/to/project --dry-run
./scripts/ccb.sh upgrade /path/to/project --yes
./scripts/ccb.sh upgrade /path/to/project --ponytail-mode lite --yes
```

The only supported path is `1.6.0 -> 1.6.1`. The upgrade prints a complete plan in a stable order, then uses `CREATE`, `UPDATE`, `SKIP`, or `CONFLICT` for each managed file. It never overwrites a file that differs from the exact generated CCB forms.

`--dry-run` is read-only: it does not create project files, directories, temporary target files, permissions changes, Git activity, or network activity. A non-interactive upgrade requires `--yes`; without it the command exits with code `2` after showing its plan.

The migration preserves the project name, profile, provider, and valid custom model choices. It creates `.ccb/skills.conf`, updates only known V1.6.0 forms, and uses atomic replacements with a best-effort rollback if a later write fails.

Exit status: `0` for a valid dry-run, successful upgrade, up-to-date project, or cancellation; `1` for invalid projects, unsupported versions, conflicts, or write errors; `2` for invalid usage or a missing non-interactive confirmation.
