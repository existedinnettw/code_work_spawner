# Config Examples

The repo uses an Agent Orchestrator style YAML config with `defaults` and `projects`.

Project entries can override `issueAssistant` fields when a repo needs a
different prompt, mention triggers, responder chain, notification list, or
event source.

GitHub projects default to `gh/polling`, and Gitea projects default to
`tea/polling`. GitHub projects can switch their long-running runtime to
`gh/gosmee` or `gh/webhook-forward`, and Gitea projects can switch to
`tea/gosmee`.
`gh/gosmee` creates a temporary GitHub webhook that targets a generated gosmee
URL. `gh/webhook-forward` starts `gh webhook forward` for `issues` and
`issue_comment` events. `tea/gosmee` creates a temporary Gitea webhook that
targets a generated gosmee URL. Channel-based event sources always run one
startup reconciliation poll. Set `reconciliation: continuous` plus
`reconcileInterval` to keep periodic reconciliation active for missed-event
recovery, or use `reconciliation: startup-only` to skip background polling
after startup. `--once` still uses a single polling reconciliation cycle so
existing backlog handling keeps working.

Use a nested `issueAssistant.eventSource` object so source-specific fields stay
grouped with the selected source type. For example:

```yaml
issueAssistant:
  eventSource:
    type: gh/webhook-forward
    reconciliation: continuous
    reconcileInterval: 300s
```

```yaml
issueAssistant:
  eventSource:
    type: gh/polling
    pollInterval: 30s
```

Generated comments include both a visible prefix and footer by default so it is
clear the reply came from automation even when `gh` or `tea` is authenticated
as a human account. Those markers support template variables such as
`{{tracker_login}}`, `{{tracker_cli}}`, `{{repo}}`, `{{project_key}}`,
`{{issue_number}}`, `{{trigger}}`, `{{comment_tag}}`, and `{{fingerprint}}`.
`{{gh_login}}` is still populated for backward compatibility. Set either
template to an empty string to disable that section.

Discord notifications are configured under `issueAssistant.notifications`.
Currently supported fields are:

- `type: discordWebhook`
- `enabled`
- `events`: any of `mention_detected`, `reply_posted`, `no_reply`, `responder_failed`
- `webhookUrl`
- `username`
- `avatarUrl`

Start from [`examples/simple-github.yaml`](simple-github.yaml) for GitHub or
[`examples/simple-gitea.yaml`](simple-gitea.yaml) for Gitea. This repo uses
`dataDir`, `worktreeDir`, and `projects`, and uses `worktreeDir` for
bug-verification worktrees.
