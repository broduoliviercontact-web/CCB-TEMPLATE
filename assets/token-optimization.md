# Token optimization

- Prefer the Tilth MCP tools for symbol search, dependency analysis and targeted code reads.
- Use ordinary reads for small files or when Tilth omits information needed for a correct answer.
- Use RTK for verbose Git, test, build and log commands; rerun a focused raw command when RTK omits needed details.
- Never trade correctness, safety or validation evidence for fewer tokens. RTK estimates filtered terminal output, not a guaranteed reduction of total Claude usage.
- Keep responses concise by default: do not restate the request or add a preamble.
- Prefer targeted changes to broad rewrites; provide detail when the user asks for it or validation evidence requires it.
