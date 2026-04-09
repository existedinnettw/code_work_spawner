# arch


## coding flow 

```mermaid
flowchart TD
	n4["agents implement"]
	n5["agents create worktree, branch"]
	n5
	n5 --> n4
	n6["create PR"]
	n8["human merge"]
	n9@{ shape: "diam", label: "human review" }
	n5["agents create worktree, branch"]
	n10@{ shape: "diam", label: "infra CI" }
	n4
	n10
	n10 -->|"y"| n9
	n9 -->|"y"| n8
	n4 --> n6
	n6["upsert PR"] --> n10
	n10 -->|"n"| n4
	n9 -->|"n"| n4
	style n1 fill:#5CE1E6
	style n7 fill:#C1FF72
	style n9 fill:#C1FF72
	style n8 fill:#C1FF72
	style n3 fill:#5CE1E6
	subgraph s1["planing stage"]
		n3["issue session in chat"]
		n11["agents propose plan"]
		n2["agents propose plan"]
		n7@{ shape: "diam", label: "user review plan" }
		n1["create issue"]
	end
	n1
	n1
	n7
	n7
	n7
	n7 -->|"y"| n5
	n7
	n2 --> n7
	n7 -->|"n: human prompt"| n2
	n1 --> n2
	n2 -->|"split to issues"| n1
	n11 --> n7
	n7 -->|"n: human prompt"| n11
	n11
	n11
	n3 --> n11
	n11 -->|"split to issue sessions"| n3
```


## arch

```mermaid
flowchart
	s2
	s2
	s2
	s2
	s2
	n3["ssh"]
	subgraph s3["my pc"]
		subgraph s4["spawner"]
			n7["db for cache"]
			n6["config file"]
			n2["codex2"]
			n5["codex1"]
		end
	end
	s2
	s2
	s2
	s2
	n3 --> s3
	s2
	s4
	s4 -->|"report execute status through API"| s2
	n1@{ label: "Rectangle" }
	n1["runners dashboard"]
	s3
	n1 --> s4
	subgraph s5["github"]
		subgraph s2["middle record server"]
			n4["db<br>save tmux session id, or codex session id, success/fail..."]
		end
		s1["workflow dashboard"]
	end
	s1 --> s2
	n8["github polling"]
	n9["github webhook + webhook-websocket gateway"]
	s2 --> n8
	n8 --> s4
	s2 --> n9
	n9 --> s4
```

## config option

* (issue) tracker
	* github(`gh`)
		* polling
		* `gh webhook forward`
		* webhook + smee.io(`gosmee`)
	* gitlab(`glab`)
		* webhook + smee.io
	* gitea(`tea`)
		* webhook + smee.io
	* openproject(`openproject-cli`)
		* polling
	* linear(`linear`)
* SCM
	* github
	* gitlab
	* gitea
* notifier
	* desktop
	* discord
	* slack
	* email
