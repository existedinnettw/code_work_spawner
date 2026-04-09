# code_work_spawner

Repository issue thread assistant with an Agent Orchestrator style YAML config.

It consumes issue tracker events for configured GitHub, Gitea, or OpenProject
projects, reads issue threads, and uses CLI responders such as `codex`, `opencode`, or
`copilot-cli` to decide when to reply. It supports
multi-repo config, responder fallback chains, and optional Discord webhook and
desktop notifications. Repository access is configured separately through each
project's `scm` block so tracker and checkout handling can evolve
independently.

## Highlights

- Consume GitHub, Gitea, and OpenProject issue events across multiple projects
- Trigger replies from mentions or meaningful thread updates
- Run planning and bug-verification flows in isolated worktrees
- Send optional Discord or desktop notifications for assistant events

## Requirements

- Dart SDK
- `gh`, `tea`, and/or OpenProject API credentials authenticated for the target projects
- Local checkouts for configured repositories
- Optional local responder CLIs such as `codex`, `opencode`, or `copilot-cli`

## Config

Create a local `agent-orchestrator.yaml` and use
[`examples/README.md`](examples/README.md) plus
[`examples/simple-github.yaml`](examples/simple-github.yaml) as the reference.

Environment placeholders such as `${CWS_DISCORD_WEBHOOK}` are resolved from the
process environment and from a `.env` file placed next to the selected config
file. Logging also supports `CWS_LOG_LEVEL` (or `LOG_LEVEL`) with values such
as `trace`, `debug`, `info`, `warning`, `error`, or `fatal`. See
[.env.example](.env.example) for a minimal starter file.

Generate a starter config:

```bash
dart run bin/code_work_spawner.dart init-config
# Write it to a file:
dart run bin/code_work_spawner.dart init-config --output agent-orchestrator.yaml
# Overwrite an existing file:
dart run bin/code_work_spawner.dart init-config --output agent-orchestrator.yaml --force
```

## Run

```bash
dart run build_runner build --delete-conflicting-outputs
```

Single event-source reconciliation cycle:

```bash
dart run bin/code_work_spawner.dart --once
```

Long-running tracker runtime:

```bash
dart run bin/code_work_spawner.dart
```

Override tracker CLI paths when needed:

```bash
dart run bin/code_work_spawner.dart \
  --config /path/to/agent-orchestrator.yaml \
  --db /path/to/state.sqlite3 \
  --gh-command /usr/bin/gh \
  --tea-command /usr/bin/tea
```

## Testing

```bash
dart run tool/validate_gherkin_test_format.dart
dart analyze
dart test
```

## ref

[agent-orchestrator](https://github.com/ComposioHQ/agent-orchestrator)
