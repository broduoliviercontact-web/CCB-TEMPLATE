# Getting Started

From a Git repository containing this template:

```sh
./scripts/install-project.sh
./scripts/validate-ccb.sh
```

The installer creates only missing directories and appends ignore entries without replacing an
existing `.gitignore`. The validator checks the persistent policy and memory files; it does
not start CCB or inspect provider credentials.

Before starting an isolated developer worktree, create an initial Git commit so `HEAD` exists.
