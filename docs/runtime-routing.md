# Ollama runtime routing

CCB supports one runtime provider: Ollama. Agent execution follows:

```text
agent-launcher.sh → provider-router.sh → runtime/provider-ollama.sh → ollama
```

The runtime contract uses exit codes 0 (success), 1 (model/runtime failure), 2 (usage or provider
error), 3 (Ollama unavailable), and 4 (unsupported direct cloud-api mode). No command performs
`ollama pull` or `ollama signin`. Use `./scripts/ccb.sh providers`, `provider check ollama`, and
`provider models ollama` for read-only diagnostics.
