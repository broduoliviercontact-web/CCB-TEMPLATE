# Local workflow execution

CCB executes a resumed workflow step only through local Ollama. Prompts are assembled from the immutable run snapshot, bounded to 1 MiB, and never persisted in metadata. Responses are bounded to 256 KiB, treated as opaque data, and published atomically to `result.md`; no Markdown, HTML, command substitution, backtick, or code fence is executed.

`execution.conf` records provider, model, attempt, timestamps, status, and a short error code. D2 does not retry a failed record. The execution lock covers one provider call, while the separate orchestration lock covers the complete sequential loop.
