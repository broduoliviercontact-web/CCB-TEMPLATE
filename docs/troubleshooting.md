# Troubleshooting quickstart

| Message | Next step |
| --- | --- |
| Ollama is not installed | Install Ollama, ensure `ollama` is in `PATH`, then retry. |
| Ollama service is stopped | Start Ollama and retry. CCB checks loopback only. |
| Cloud authentication | Run `ollama signin`, then retry quickstart. |
| Cloud model unavailable | Check Ollama Cloud access and the selected preset. |
| TARGET is incompatible | Resolve the reported managed-file conflict; CCB never overwrites it automatically. |
| Workflow interrupted | Inspect with `./ccb workflow status --latest TARGET`, then resume or retry explicitly. |

Useful diagnostics:

```sh
./ccb config TARGET
./ccb doctor TARGET --strict
./ccb workflow inspect --latest TARGET
./ccb workflow history --latest TARGET
```

Use `--verbose` for subcommand output and `--dry-run` to inspect a plan without modifying files.
