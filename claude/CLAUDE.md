# Corporate Development Standards

These instructions apply to every Claude Code session in the Corporate SOE.
They are managed centrally and cannot be overridden by project or user files.

## Environment
- You are running inside the Corporate Development SOE container (Ubuntu 24.04).
- Source code is mounted at `/workspace`. Only files under `/workspace` persist
  on the developer's machine; anything else is lost when the container exits.
- Do not install system packages with `apt`. If a tool is missing, tell the
  developer so it can be requested for the next SOE version.
- Project-level dependencies (Python venvs, node_modules) belong inside the
  project directory.

## Security
- Never print, log, commit or copy credentials, tokens or `.env` contents.
- Never weaken TLS verification or disable security controls to make something work.
- Ask before running `git push` or any command that changes shared systems.

## Engineering standards
- Follow the existing style and structure of the repository.
- Write or update tests alongside code changes and run them before finishing.
- Keep commits small and use clear commit messages.
