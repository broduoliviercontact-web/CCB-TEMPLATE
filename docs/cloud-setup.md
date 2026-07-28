# Ollama Cloud setup

Install Ollama separately and sign in before using Cloud quickstart:

```sh
ollama signin
./ccb quickstart "$HOME/topchef" --profile web --cloud --run feature --yes
```

CCB uses Ollama through `http://127.0.0.1:11434` and `http://localhost:11434` only. It performs a
small Cloud probe with the selected model, never stores credentials, and never prints tokens or
cookies. The `coding-cloud` preset selects:

| Role | Model |
| --- | --- |
| Manager | `glm-5.2:cloud` |
| Graph | `qwen3.5:397b-cloud` |
| Graphiste | `gemma4:31b-cloud` |
| Developer | `kimi-k2.7-code:cloud` |
| Reviewer | `deepseek-v4-pro:cloud` |
| Fallback | `qwen3-coder:480b-cloud` |

Cloud quickstart never runs `ollama pull` and never selects `qwen3:8b` or
`qwen2.5-coder:7b`. Local execution remains available through the existing explicit workflow
commands and local model configuration.
