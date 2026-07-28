# Local workflow execution

CCB executes a resumed workflow step only through local Ollama. Prompts are assembled from the immutable run snapshot, bounded to 1 MiB, and never persisted in metadata. Responses are bounded to 256 KiB, treated as opaque data, and published atomically to `result.md`; no Markdown, HTML, command substitution, backtick, or code fence is executed.

Before publishing `result.md`, V1.8.0 guarantees one line boundary after the opaque provider
response when it is missing. A response that already ends in a newline is left unchanged. This
keeps CCB's `END PREVIOUS RESULT` delimiter on its own line during `complete-step`, without
interpreting or rewriting the useful response body.

`execution.conf` records provider, model, attempt, timestamps, status, and a short error code. D3 still performs no automatic retry: `workflow retry-step` must be invoked explicitly after failure and permits at most three attempts. Each finished failure preceding the current attempt is archived as strictly parsed `attempts/001.conf` through `003.conf`. Archives contain only bounded execution metadata—never prompts, responses, Markdown, cookies, tokens, or secrets.

Retry preparation uses confined temporary data, atomic file replacement, and logical rollback. Test fail points are enabled only with `CCB_TEST_MODE=1`. The execution lock covers one provider call, while the separate orchestration lock covers the complete sequential loop. Only local loopback Ollama is supported; there is no remote provider or fallback.

Role-based model files and historical V1.7.0 model files are both accepted. New role-based files
preserve distinct manager, graph, graphiste, developer, and reviewer choices in workflow
snapshots; historical planner/coder assignments retain their documented compatibility mapping.
