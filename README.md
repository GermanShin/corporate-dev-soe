# Corporate Development SOE

A standard, self-provisioning Ubuntu sandbox with Claude Code, published to ECR
and run locally on macOS (or Linux/Windows) through Docker.

| Path | Purpose |
|---|---|
| `Dockerfile` | The SOE image: OS, tools, Claude Code, corporate policy |
| `bootstrap/install-tools.sh` | **Build time** - packages, AWS CLI, `dev` user |
| `bootstrap/entrypoint.sh` | Container start - optional firewall, drop to `dev`, bootstrap |
| `bootstrap/bootstrap.sh` | **Run time, idempotent** - per-developer provisioning |
| `bootstrap/configure-claude.sh` | Syncs corporate skills/agents into the developer's volume |
| `bootstrap/configure-network.sh` | Optional default-deny egress allowlist |
| `bootstrap/soe-doctor.sh` | Health check (`soe-doctor` inside the container) |
| `claude/managed-settings.json` | Locked Claude Code policy (`/etc/claude-code`) |
| `claude/CLAUDE.md` | Locked corporate instructions (`/etc/claude-code`) |
| `claude/skills`, `claude/agents` | Corporate skills and subagents |
| `config/apt-packages.txt` | Packages baked into the image |
| `config/allowed-domains.txt` | Firewall allowlist |
| `config/soe.env.example` | Developer launcher settings |
| `scripts/start-dev.sh` | Developer launcher (install as `soe`) |
| `scripts/publish.sh` | Multi-arch build + push to ECR |
| `buildspec.yml` | CodeBuild pipeline |
| `docker-compose.yml` | Local build/test for the platform team |

Quick start for developers:

```bash
sudo install -m 0755 scripts/start-dev.sh /usr/local/bin/soe
mkdir -p ~/.config/corporate-soe && cp config/soe.env.example ~/.config/corporate-soe/soe.env
cd ~/code/my-project && soe
```

See the step-by-step guide for the full walkthrough.
