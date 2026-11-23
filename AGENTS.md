# Specwright workflow

- Read the installed version from [`openspec/.specwright/VERSION`](openspec/.specwright/VERSION). Use the matching `~/.specwright/bin/<VERSION>/sw` (`sw.exe` on Windows); if `SPECWRIGHT_HOME` is set, use it instead of `~`. Before the first command, check that `sw version --json` reports the stamped version and interface 3.
- If the binary is missing or mismatched, follow the [Specwright 0.39.1 install instructions](https://github.com/sh1ny/specwright/blob/v0.39.1/README.md) and restart the agent session. Use OpenSpec 1.16.0 (`npm install -g @fission-ai/openspec@1.16.0`).
- Follow the branch, apply and archive gates in [`openspec/config.yaml`](openspec/config.yaml). Preserve project workflow settings in [`openspec/specwright.yaml`](openspec/specwright.yaml).
- Fence GitHub CLI calls with `sw as <login>` and use `sw vcs` with `--login` for network Git writes. Do not switch the globally active GitHub account.
