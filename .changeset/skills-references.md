---
'better-supabase': patch
---

Agent skills are now task workflows with a "Done when" check for each, plus reference files:
`references/plugins.md` and `references/troubleshooting.md` (every `DbError` kind and its usual
cause) for `better-supabase`, and `references/adapters.md` for `better-supabase-api`.
`better-supabase skills install` copies the reference files next to each `SKILL.md`, and `--check`
compares them too. The skills help mentions `npx skills add ScaleDockHQ/better-supabase` for other
agents, and the main skill points at the Markdown docs (`/docs/<path>.md`). The package now ships a
README for npm.
