# Minimal project bootstrap

Use `./scripts/ccb.sh init TARGET` to create the smallest local CCB project contract. It supports `generic` (the default), `web`, `node`, `python`, and `audio`. The command does not access the network, initialize Git, install software, download models, or call a provider.

```sh
./scripts/ccb.sh init ./my-project --yes
./scripts/ccb.sh init ./my-project
./scripts/ccb.sh init ./my-project --dry-run
```

The managed files are exactly `.ccb/project.conf`, `.ccb/models.conf`, `.ccb/skills.conf`, `.ccb/context/project.md`, and `AGENTS.md`. Ponytail defaults to enabled `full` mode and can be set with `--ponytail-mode off|lite|full|ultra`; no plugin is installed automatically.

Before writing, the command prints a complete plan for all managed files: `CREATE` for an absent path, `SKIP` for an identical regular file, and `CONFLICT` for different content, a symbolic link, a non-regular file, or an incompatible parent. A conflict exits with status 1 and prevents every write. A second identical invocation therefore reports four `SKIP` entries. A V1.6.0-B project has different managed-file contents, so it deliberately conflicts rather than being silently migrated.

`--dry-run` performs the same analysis but creates no target, directory, or managed file. It exits 0 without a conflict and 1 with one. Invalid arguments, unsafe paths, unsupported profiles, and a required non-interactive confirmation exit 2.

Each created file is first written to a private temporary file in its final directory. All temporary files are prepared before any rename finalizes a file; each individual finalization is atomic on that filesystem. A shell cannot make three independent renames a perfect transaction: if a later rename fails after an earlier one succeeds, the earlier file is retained rather than risking deletion of an ambiguous final file. Temporary files are cleaned on normal exit and HUP, INT, or TERM.

For safety, the command rejects the filesystem root, the user home directory, the template repository, `.git` path components, target symlinks, managed-file symlinks, and incompatible `.ccb` parents. Project names are written literally; they are never evaluated as shell code.

## Profiles and model routing

`web` adds browser, accessibility, and client-secret guidance; `node` checks package and runtime conventions; `python` respects virtual environments; and `audio` emphasizes real-time safety. Model names allow only letters, digits, `.`, `_`, `-`, `/`, and `:`. The defaults are `qwen3:8b` for default, planner, and reviewer roles, and `qwen2.5-coder:7b` for coding.

Use `--model` to replace all profile defaults, then role-specific options to take precedence:

```sh
./scripts/ccb.sh init ./site --profile web --model qwen3:8b --coder-model qwen2.5-coder:7b --yes
./scripts/ccb.sh config ./site
```

`config` safely parses and prints project and model data; it makes no network request and never invokes Ollama.
