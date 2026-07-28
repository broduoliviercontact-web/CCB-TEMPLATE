# CCB Quickstart

`./ccb quickstart TARGET` is the supported first-install path for V1.8.0.

```sh
./ccb quickstart "$HOME/topchef" --name "TopChef" --profile web --cloud --run feature --yes
```

The command checks the local Ollama service, validates Cloud access when `--cloud` is used,
bootstraps the seven project files, writes the role-based model configuration, runs Config and
Doctor strict, creates the requested workflow, verifies its model snapshot, and runs it when
`--run` is present. Without `--run`, no workflow run is created. `--no-run` makes this explicit.

Defaults are `generic`, the basename of `TARGET`, Ollama, full Ponytail rules, and no workflow.
`--name` is an alias for `--project-name`. Supported profiles are `generic`, `web`, `node`,
`python`, and `audio`.

Use `--dry-run` to print the plan without changing the target. Use `--force-new` to choose a new
safe sibling such as `topchef-2`; it never overwrites an existing project. Repeating a successful
quickstart is idempotent and skips already-valid configuration.

Quickstart records the pre-existing managed files and removes or restores only files it changed
if a later stage fails. It refuses symlinks, unsafe paths, incompatible managed files, and writes
outside the target. Test-only `CCB_TEST_MODE=1` hooks can inject failures at bootstrap, config, or
Doctor stages; they are never active in production.
