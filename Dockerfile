# syntax=docker/dockerfile:1.7
# -----------------------------------------------------------------------------
# Corporate Development SOE (Standard Operating Environment)
#
# Everything that is the SAME for every developer is baked in here at build
# time (OS, tools, Claude Code, corporate policy, skills, agents).
# Everything that is PERSONAL is provided at run time (source code, AWS
# credentials, Claude login/settings volume) - see scripts/start-dev.sh.
# -----------------------------------------------------------------------------
FROM ubuntu:24.04

ARG SOE_VERSION=1.0.0
# "stable", "latest" or an exact version such as "2.1.80". Pin for production.
ARG CLAUDE_CODE_VERSION=stable
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

LABEL org.opencontainers.image.title="corporate-dev-soe" \
      org.opencontainers.image.description="Corporate development sandbox with Claude Code" \
      org.opencontainers.image.version="${SOE_VERSION}"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=Etc/UTC

# 1. OS packages, AWS CLI v2 and the non-root developer user (build time only,
#    so containers start in seconds and never run apt-get).
COPY config/apt-packages.txt bootstrap/install-tools.sh /tmp/soe/
RUN USERNAME="${USERNAME}" USER_UID="${USER_UID}" USER_GID="${USER_GID}" \
    bash /tmp/soe/install-tools.sh && rm -rf /tmp/soe

# 2. Claude Code, installed as the developer user with the native installer.
USER ${USERNAME}
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}" \
 && /home/${USERNAME}/.local/bin/claude --version
USER root

# 3. Corporate policy. Files under /etc/claude-code are "managed" and cannot be
#    overridden by developer or project settings.
COPY claude/managed-settings.json /etc/claude-code/managed-settings.json
COPY claude/CLAUDE.md             /etc/claude-code/CLAUDE.md

# 4. Corporate skills/agents (seeded into each developer's config by bootstrap)
#    plus the bootstrap scripts themselves.
COPY claude/skills  /opt/corporate-soe/claude/skills
COPY claude/agents  /opt/corporate-soe/claude/agents
COPY config/allowed-domains.txt /opt/corporate-soe/config/allowed-domains.txt
COPY bootstrap/entrypoint.sh bootstrap/bootstrap.sh bootstrap/configure-claude.sh \
     bootstrap/configure-network.sh bootstrap/soe-doctor.sh /opt/corporate-soe/bootstrap/
RUN chmod 0755 /opt/corporate-soe/bootstrap/*.sh \
 && chmod -R a+rX /opt/corporate-soe /etc/claude-code \
 && ln -sf /opt/corporate-soe/bootstrap/soe-doctor.sh /usr/local/bin/soe-doctor \
 && echo "${SOE_VERSION}" > /opt/corporate-soe/VERSION

ENV SOE_USER=${USERNAME} \
    HOME=/home/${USERNAME} \
    PATH=/home/${USERNAME}/.local/bin:${PATH} \
    CLAUDE_CONFIG_DIR=/home/${USERNAME}/.claude \
    DISABLE_AUTOUPDATER=1

WORKDIR /workspace

# The entrypoint starts as root only long enough to apply the optional egress
# firewall, then drops to the developer user and runs the idempotent bootstrap.
ENTRYPOINT ["/opt/corporate-soe/bootstrap/entrypoint.sh"]
CMD ["bash", "-l"]
