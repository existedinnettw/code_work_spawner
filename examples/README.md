# Config Examples

The repo uses an Agent Orchestrator style YAML config with `defaults` and `projects`.

Project entries can override `issueAssistant` fields when a repo needs a
different prompt, mention triggers, or responder chain.

Generated comments include both a visible prefix and footer by default so it is
clear the reply came from automation even when `gh` is authenticated as a human
account. Those markers support template variables such as `{{gh_login}}`,
`{{repo}}`, `{{project_key}}`, `{{issue_number}}`, `{{trigger}}`,
`{{comment_tag}}`, and `{{fingerprint}}`. Set either template to an empty
string to disable that section.

Start from [`examples/simple-github.yaml`](simple-github.yaml). This
repo uses `dataDir`, `worktreeDir`, and `projects`, and uses `worktreeDir` for
bug-verification worktrees.
