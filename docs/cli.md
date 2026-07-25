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

`--ascii` or `CCB_ASCII=1` uses an ASCII banner. `NO_COLOR=1` is respected; ordinary command
output is already plain text. Help succeeds with status 0, unknown commands return 2, and an
unknown profile returns 1. The CLI delegates work to the existing scripts; it does not execute
profile content or construct commands for a shell.
