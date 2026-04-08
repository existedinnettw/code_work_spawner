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
URL, then keeps the same polling reconciliation path active for startup sync
and missed-event recovery.
`gh/webhook-forward` starts
`gh webhook forward` for `issues` and `issue_comment` events while keeping
periodic polling reconciliation for startup sync and missed-event recovery.
`tea/gosmee` creates a temporary Gitea webhook that targets a generated gosmee
URL, then keeps the same polling reconciliation path active for startup sync
and missed-event recovery. `--once` still uses a single polling reconciliation
cycle so existing backlog handling keeps working.

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
