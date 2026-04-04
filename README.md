# code_work_spawner

GitHub issue thread assistant with an Agent Orchestrator style YAML config.

The app polls configured GitHub repositories with `gh`, reads issue threads and
issue comments, and uses configured CLI responders such as `codex`,
`opencode`, or `copilot-cli` to reply when:

- a user explicitly mentions the assistant
- a new comment changes the thread enough that the responder decides a reply is
  useful

It supports multi-repo configuration, responder fallback chains.

## Features

- Agent Orchestrator style YAML config with `defaults` and `projects`
- Multiple repositories in one process
- Comment-triggered issue assistance
- Planning / architecture guidance in issue threads
- Bug verification flows in isolated temporary git worktrees
- CLI-based responder fallback chain
- Durable state with `drift` + SQLite
- BDD-style tests using `package:test` with Given / When / Then wording

## Requirements

- Dart SDK
- `gh` CLI authenticated for the target repositories
- Local checkouts for configured repositories
- Optional local responder CLIs such as `codex`, `opencode`, or `copilot-cli`

## Config

Create a local `agent-orchestrator.yaml` and follow [`/examples/README.md`](examples/README.md) as a starting point.

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

Single poll cycle:

```bash
dart run bin/code_work_spawner.dart --once
```

Long-running poller:

```bash
dart run bin/code_work_spawner.dart
```

Override paths when needed:

```bash
dart run bin/code_work_spawner.dart \
  --config /path/to/agent-orchestrator.yaml \
  --db /path/to/state.sqlite3 \
  --gh-command /usr/bin/gh
```

## Testing

```bash
dart run tool/validate_gherkin_test_format.dart
dart analyze
dart test
```

All Dart tests under `test/` must follow the repo's Gherkin doc-comment format:

- `group(...)` has a `Feature` doc block above it
- `test(...)` has a `Scenario` doc block above it
- runtime names stay plain, without `Feature:` or `Scenario:` prefixes
- test bodies include `Given` / `When` / `Then` inline comments

## ref

[agent-orchestrator](https://github.com/ComposioHQ/agent-orchestrator)
