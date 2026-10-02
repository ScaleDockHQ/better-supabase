---
"better-supabase": minor
---

`createMcp` takes `allowedHosts`, which rejects requests whose `Host` header names another host (DNS rebinding protection, next to `allowedOrigins`), and `resourceDocumentation`, published as RFC 9728 `resource_documentation` in the protected resource metadata.
