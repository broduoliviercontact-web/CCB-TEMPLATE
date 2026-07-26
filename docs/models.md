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
