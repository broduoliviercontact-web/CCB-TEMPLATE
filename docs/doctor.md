# CCB Doctor

`./scripts/ccb.sh doctor [TARGET]` is a read-only diagnostic. Without a target
it checks the template; with a target it also checks the four bootstrap-managed
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

Individual file writes from bootstrap are atomic, but a multi-file bootstrap
cannot be a perfect shell transaction if a late rename fails.
