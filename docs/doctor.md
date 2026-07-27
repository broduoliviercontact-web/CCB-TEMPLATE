# CCB Doctor

`./scripts/ccb.sh doctor [TARGET]` is a read-only diagnostic. Without a target
it checks the template; with a target it also checks the five bootstrap-managed
files, profile, model routing, permissions, and lightweight Git state.

```sh
./scripts/ccb.sh doctor
./scripts/ccb.sh doctor ./mon-projet --no-ollama
./scripts/ccb.sh doctor ./mon-projet --strict
```

Results use `OK`, `WARN`, `FAIL`, and `SKIP`. Normal mode exits 0 when there is
no `FAIL`; `--strict` also exits 1 for a warning. Invalid usage exits 2.
`--no-ollama` prints an explicit skip. An absent Ollama command is normally a
warning, not a failure.

Doctor parses `.ccb/project.conf` and `.ccb/models.conf` as declarative data;
it never evaluates them. It may call only `ollama --version` and `ollama list`.
It never downloads, runs, starts, modifies, or removes models, and it never
repairs project files or permissions. The text format is the supported stable
format in V1.6.0.

A valid bootstrap project at template version `1.6.0` receives a `WARN` that
skills are not configured and an explicit `ccb upgrade TARGET --yes` recommendation.
Doctor remains read-only: it does not start an upgrade.

For a 1.7.0 project Doctor validates `agents.conf` as data and reports that access is declarative only. A 1.6.1 project without this file remains readable and receives a compatibility warning; no 1.6.1 to 1.7.0 migration is performed.

Individual file writes from bootstrap are atomic, but a multi-file bootstrap
cannot be a perfect shell transaction if a late rename fails.
