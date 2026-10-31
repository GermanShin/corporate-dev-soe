---
name: corp-secure-coding
description: Corporate secure-coding checklist. Use when writing or reviewing code that handles input, authentication, secrets, file access, SQL or external calls.
---

# Corporate secure-coding checklist

Apply these checks to any code you write or review:

1. **Input** - validate and bound all external input; never build SQL, shell
   commands or file paths by string concatenation.
2. **Secrets** - read secrets from the environment or AWS Secrets Manager; never
   hard-code them, log them or write them to disk.
3. **Auth** - every new endpoint must state who can call it and enforce it.
4. **Dependencies** - prefer existing approved libraries; pin versions.
5. **Errors** - fail closed; don't leak stack traces or internal details to users.
6. **Logging** - log security-relevant events without personal data.

When finished, summarise which checks applied and anything that still needs a human decision.
