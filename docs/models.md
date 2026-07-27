# Agent models

CCB stores only non-secret Ollama assignments in `.ccb/models.conf`. Use the declarative presets
with `./scripts/ccb.sh models presets`, then configure safely:

```sh
./scripts/ccb.sh models setup . --preset balanced-cloud --yes
./scripts/ccb.sh models setup . --single-model qwen3.5:cloud --yes
./scripts/ccb.sh models setup . --preset balanced-cloud --dry-run
./scripts/ccb.sh models resolve developer
```

The six presets are suggestions only; a model not detected locally remains valid. CCB never runs
`ollama pull` or `ollama signin`, and never writes API keys. Replacements are atomically written
and the old configuration is retained as a timestamped backup.

V1.7.1 uses one strict parser for validation, Config, Doctor, model display, model resolution,
and workflow snapshots. It accepts both configuration schemas:

- the role schema written by `models setup`, with separate manager, graph, graphiste, developer,
  reviewer, and fallback assignments;
- the historical V1.7.0 schema with default, planner, coder, and reviewer assignments.

For historical files, manager, graph, and graphiste resolve to planner; developer resolves to
coder; reviewer remains reviewer; and fallback resolves to default. Existing V1.7.0 projects do
not require migration. `models show` renders only validated non-secret fields and never prints
tokens, cookies, or credentials.
