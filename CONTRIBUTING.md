# Contributing to Yagura

Thanks for helping. Yagura is a self-hosted game server manager: a headless Dart daemon (`yagurad`) that installs, configures and runs dedicated game servers on Windows, and a Flutter desktop client that manages several daemons over mTLS gRPC. Every game is a plugin: a YAML manifest plus optional JavaScript hooks.

Yagura is pre-release. Milestones and their state are in the [roadmap](openspec/roadmap.md). Windows comes first; Linux later.

## Ways to help

- **Report a bug or suggest an idea.** Open an [issue](https://github.com/sh1ny/yagura/issues/new/choose). The forms say what helps; only the first box is required.
- **Fix something small** (a typo, a doc, an obvious bug): send a pull request straight away.
- **Anything bigger** (a new feature, a new dependency, or a change to how the parts talk to each other): open an issue first, so we can agree on the approach before you spend time on it.
- **Found a security problem?** Don't open an issue. Report it privately as [SECURITY.md](SECURITY.md) describes.

## How the project is planned

Maintainers plan work with [OpenSpec](https://github.com/Fission-AI/OpenSpec) and [Specwright](https://github.com/sh1ny/specwright): milestones live in `openspec/roadmap.md` and each larger change gets a folder under `openspec/changes/`. You don't need either tool to contribute. If your change is larger, a maintainer may write it up as an OpenSpec change and ask you a question or two. Please don't edit `openspec/changes/` in your pull request unless you're asked to.

Much of the maintainers' own work is done with AI coding agents, and an automated reviewer may comment on your pull request. A person makes every decision. AI-assisted contributions are welcome too, as long as you understand and have tested what you send.

## Setup

Install [mise](https://mise.jdx.dev/) and Git. `mise install` installs the pinned Flutter (with Dart), protoc and git-cliff.

```sh
mise install
mise run analyze
mise run test
mise run format:check
```

Start with [docs/overview.md](docs/overview.md); it explains how the daemon, the desktop app and plugins fit together, with an example plugin.

## Making a change

- Branch from `main` and keep each pull request to one change.
- **Tests.** Add or update tests for behaviour you change. A test must never fail because a machine is slow: wait for an event or a result, never sleep for a fixed time.
- **Commit messages** follow [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): summary`, for example `fix(map): show transits on Reserve`. If you get it wrong, a maintainer will fix it when merging.
- **Write it yourself.** Don't copy code from other projects, including translating it from another language. Adding a dependency is fine when its licence is compatible, but mention it in the pull request.

### Rules specific to Yagura

- **Game plugins are the easiest way in.** A new game is a YAML manifest plus optional JavaScript hooks; [docs/overview.md](docs/overview.md) has an example. You don't need to touch the daemon to add one.
- The desktop and the daemon only talk through the gRPC protocol in `proto/yagura/v1/`. A protocol change is a bigger change, so open an issue first.
- Checks that need a real game server (installing it, Steam Guard, mods) are run by hand by the maintainer. Say in your PR what you couldn't test; that's expected.

## Pull requests

The template asks for three things: a short **Summary**, what it's **Linked** to (an issue, or "none"), and how you **tested** it. Everything else is optional.

CI runs on every pull request. If it fails and you can't see why, say so in the pull request and we'll help. A maintainer reviews and merges.

## Licence

By contributing, you agree that your contribution is licensed under the project's [Apache-2.0 licence](LICENSE). Game plugins in `plugins/` are under the [MIT licence](plugins/LICENSE), so plugin contributions are MIT-licensed.
