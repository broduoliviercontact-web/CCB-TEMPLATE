# V2 Complexity Router

The Complexity Router classifies each CCB task into one of three levels before
delegation, so the manager uses the smallest agent set that reaches the required
confidence level. It is advisory: the user can override the recommendation.

The router preserves every existing CCB behavior. Without the optional
`--complexity` flag, the manager prompt keeps its current wording and only the
shared `AGENT_POLICY.md` and manager skill mention the three levels.

## Levels

| Level    | Workflow                                                              | Reviewer           | Graph          |
| -------- | --------------------------------------------------------------------- | ------------------ | -------------- |
| SIMPLE   | Manager -> Developer -> deterministic checks                          | optional (on fail) | not invoked    |
| NORMAL   | Manager -> Developer -> Reviewer -> Manager                           | required           | on demand      |
| COMPLEX  | Manager -> [Graph on demand] -> Developer -> Reviewer -> Manager      | required           | on demand      |

### SIMPLE

Use for typos, local documentation, simple CSS, local renames, isolated fixes
and small known tests that touch roughly one to three files with no known
cross-cutting dependencies. Skip the reviewer unless a deterministic check
fails. Never invoke graph.

### NORMAL

Use for non-trivial bug fixes or small features that may span a handful of
files with a reasonable regression risk. Use developer plus reviewer. Invoke
graph only when a real ambiguity remains about dependencies or impact.

### COMPLEX

Use for refactors, architecture changes, authentication or permissions,
cross-cutting concerns, or tasks where the affected files are not yet known.
Invoke graph explicitly when the affected components or structural risks need
to be mapped, then delegate implementation to developer and independent
validation to reviewer.

## Classification heuristic

`./ccb-template classify TARGET BRIEF_FILE` runs a lightweight, deterministic
heuristic on a brief file:

- Strong keywords (refactor, architecture, auth, migration, security, schema,
  deploy, breaking, cross-cutting) recommend COMPLEX.
- Short briefs with small-edit keywords (typo, doc, css, rename, formatting)
  recommend SIMPLE.
- Anything else falls back to NORMAL.

The classification is **advisory only**. The user can override it by passing
`--complexity` to `manager-prompt`.

## CLI usage

Print the manager prompt with the chosen routing rules:

```sh
./ccb-template manager-prompt /chemin/du/projet brief-YYYYMMDD-HHMMSS.md \
  --complexity simple
```

Recommend a level from a brief:

```sh
./ccb-template classify /chemin/du/projet brief-YYYYMMDD-HHMMSS.md
```

Print the routing summary for a level:

```sh
./ccb-template route simple
./ccb-template route normal
./ccb-template route complex
```

## Operating boundaries

- The manager never implements application changes; it classifies and delegates.
- The developer is still the only agent that implements approved changes.
- The reviewer is still read-only.
- Graph stays on demand and stays read-only.
- No agent pushes, deploys, merges or changes Git history without explicit
  human authorisation.