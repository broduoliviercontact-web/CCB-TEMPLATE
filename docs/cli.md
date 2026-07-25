# CCB Control Room

Run `./scripts/ccb.sh` with no argument to open the interactive Control Room. It uses only
terminal text, never clears the screen and accepts `Q` or Ctrl+D to leave. Installation displays
the delegated command and asks for confirmation.

Non-interactive commands remain suitable for scripts and CI:

```sh
./scripts/ccb.sh doctor /path/to/project
./scripts/ccb.sh validate /path/to/project
./scripts/ccb.sh install /path/to/project --profile react-web
./scripts/ccb.sh profiles
./scripts/ccb.sh profile show generic
./scripts/ccb.sh status /path/to/project
./scripts/ccb.sh version
```

`./scripts/ccb.sh setup` (or `wizard`) starts the guided setup. For automation, use
`./scripts/ccb.sh setup TARGET --profile react-web --yes`; `--dry-run` performs the same checks
without changing files. Without `--yes`, non-interactive setup refuses to install.

`--ascii` or `CCB_ASCII=1` uses an ASCII banner. `NO_COLOR=1` is respected; ordinary command
output is already plain text. Help succeeds with status 0, unknown commands return 2, and an
unknown profile returns 1. The CLI delegates work to the existing scripts; it does not execute
profile content or construct commands for a shell.

## Animated mascots

Only a no-argument interactive session shows a short local animation. A mascot is selected once
per session from `terminal-bot`, `radio-bot`, `synth-bot`, `server-bot` and `space-bot`; command
mode never animates. Set `CCB_MASCOT=radio-bot` or pass `--mascot radio-bot` to force one.
`CCB_MASCOT_SEED` makes the local selection deterministic for tests. Set `CCB_NO_ANIMATION=1` or
pass `--no-animation` for the final frame directly. No data is sent and no dependency is used.

## Mascot moods

`neutral` means waiting; `working` marks an operation, `happy` a success, `worried` a success
with warnings, `error` a failure and `goodbye` session closure. Use `./scripts/ccb.sh mascots`,
`./scripts/ccb.sh mascot show terminal-bot`, or `./scripts/ccb.sh mascot moods --all` to browse
the local gallery. Moods never persist and command mode never animates.
