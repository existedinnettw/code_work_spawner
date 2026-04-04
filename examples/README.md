# Config Examples

The repo try to [follow Agent Orchestrator style config](https://github.com/ComposioHQ/agent-orchestrator/tree/main/examples).

Project entries can override `issueAssistant` fields when a repo needs a
different prompt, mention triggers, or responder chain.

Generated comments include both a visible prefix and footer by default so it is
clear the reply came from automation even when `gh` is authenticated as a human
account. Those markers support template variables such as `{{gh_login}}`,
`{{repo}}`, `{{project_key}}`, `{{issue_number}}`, `{{trigger}}`,
`{{comment_tag}}`, and `{{fingerprint}}`. Set either template to an empty
string to disable that section.

For a more minimal Agent Orchestrator compatible subset, start from
[`examples/simple-github.yaml`](examples/simple-github.yaml). This repo accepts
AO-style `dataDir`, `worktreeDir`, and core `projects` fields, and uses
`worktreeDir` for bug-verification worktrees.
