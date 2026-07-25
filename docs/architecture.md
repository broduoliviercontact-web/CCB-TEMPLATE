# Architecture

CCB is a workflow layer around a Git repository and managed coding agents. Persistent project
instructions live under `.ccb/`; runtime state, sessions, worktrees and backups remain local.

```text
request → manager → graph → developer (isolated worktree) → reviewer → manager
```

The template deliberately does not prescribe a programming language, UI framework, provider
or deployment system.
