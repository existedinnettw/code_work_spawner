# Config Examples

The repo uses an Agent Orchestrator style YAML config with `defaults` and `projects`.

Project entries can override `issueAssistant` fields when a repo needs a
different prompt, mention triggers, responder chain, notification list, or
event source.

Each project also has separate tracker and SCM config. `issueTracker.provider`
selects the logical tracker family, `issueTracker.eventSource.type` selects the
concrete adapter used to receive updates, and `scm.provider` selects how
temporary repo workspaces are prepared for responders. Legacy top-level project
`provider` and legacy `issueAssistant.eventSource` are still accepted during
load for backward compatibility. When `scm` is omitted it defaults to a
matching provider for existing GitHub, GitLab, and Gitea configs.

GitHub projects default to `gh/polling`, GitLab projects default to
`glab/polling`, and Gitea projects default to `tea/polling`. OpenProject
projects default to `op/polling` and currently only support polling. GitLab and
OpenProject currently support polling only. Because OpenProject issue tracking
is not tied to a repository host, OpenProject projects must set
`scm.provider` explicitly. GitHub projects can switch their long-running runtime to
`gh/gosmee` or `gh/webhook-forward`, and Gitea projects can switch to
`tea/gosmee`.
For OpenProject, `repo` may be either a numeric project id or an exact project
name.
`gh/gosmee` creates a temporary GitHub webhook that targets a generated gosmee
URL. `gh/webhook-forward` starts `gh webhook forward` for `issues` and
`issue_comment` events. `tea/gosmee` creates a temporary Gitea webhook that
targets a generated gosmee URL. Channel-based event sources always run one
startup reconciliation poll. Set `reconciliation: continuous` plus
`reconcileInterval` to keep periodic reconciliation active for missed-event
recovery, or use `reconciliation: startup-only` to skip background polling
after startup. `--once` still uses a single polling reconciliation cycle so
existing backlog handling keeps working.

Use a nested `issueTracker.eventSource` object so adapter-specific fields stay
grouped with the selected adapter key. For example:

```yaml
issueTracker:
  provider: github
  eventSource:
    type: gh/webhook-forward
    reconciliation: continuous
    reconcileInterval: 300s
```

```yaml
issueTracker:
  provider: github
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

Start from [`examples/simple-github.yaml`](simple-github.yaml) for GitHub,
[`examples/simple-gitlab.yaml`](simple-gitlab.yaml) for GitLab,
[`examples/simple-gitea.yaml`](simple-gitea.yaml) for Gitea, or
[`examples/simple-openproject.yaml`](simple-openproject.yaml) for OpenProject.
This repo uses `dataDir`, `worktreeDir`, and `projects`, and uses
`worktreeDir` for bug-verification worktrees.
