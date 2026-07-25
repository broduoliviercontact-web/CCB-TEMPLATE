# Architecture

CCB is a workflow layer around a Git repository and managed coding agents. Persistent project
instructions live under `.ccb/`; runtime state, sessions, worktrees and backups remain local
and are ignored.

```text
request → manager → graph and/or graphiste → developer (isolated worktree) → reviewer → manager
```

`graph` describes technical architecture, dependencies and code structure. `graphiste`
describes UX/UI, design tokens, layout and visual consistency from text-only evidence. The
template deliberately does not prescribe a programming language, UI framework, provider or
deployment system.
