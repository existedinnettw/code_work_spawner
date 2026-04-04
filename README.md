# code_work_spawner

GitHub issue thread assistant with Agent Orchestrator style config.

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

- Dart SDK 3.11+
- `gh` CLI authenticated for the target repositories
- Local checkouts for configured repositories
- Optional local responder CLIs such as `codex`, `opencode`, or `copilot-cli`

## Config

Create a local `agent-orchestrator.yaml`:

```yaml
defaults:
  issueAssistant:
    enabled: true
    pollInterval: 5m
    mentionTriggers: ["@helper", "@codex"]
    commentTag: code-work-spawner
    prompt: |
      You are helping on {{repo}}.
      Trigger: {{trigger}}
      Thread:
      {{thread_json}}
    responders:
      - id: codex
        command: codex
        args: ["exec", "--json"]
        timeout: 10m
      - id: opencode
        command: opencode
        timeout: 10m

projects:
  my-app:
    repo: owner/my-app
    path: ~/code/my-app
    defaultBranch: main
    sessionPrefix: app
```

Project entries can override `issueAssistant` fields when a repo needs a
different prompt, mention triggers, or responder chain.

For a more minimal Agent Orchestrator compatible subset, start from
[`examples/simple-github.yaml`](examples/simple-github.yaml). This repo accepts
AO-style `dataDir`, `worktreeDir`, and core `projects` fields, and uses
`worktreeDir` for bug-verification worktrees.

## Run

```bash
dart run build_runner build
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
