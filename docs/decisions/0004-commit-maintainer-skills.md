# 0004: Commit the maintainer skills in `.agents/skills`

- Status: accepted
- Date: 2026-10-02

## Context

ADR 0001 kept `.agents/skills` empty and ignored `skills-lock.json`, because
`.agents/skills` is a discovery root for `npx skills add` and this repo ships
its own consumer skills. That left every maintainer to install the skills the
repo work depends on (`scaledock-repo-standard` from
`ScaleDockHQ/scaledock-skills`, `security-audit` from
`cloudflare/security-audit-skill`) by hand, and agents in a fresh clone did
not see them.

## Decision

`.agents/skills` and `skills-lock.json` are committed. Maintainers add or
update a skill with `npx skills add <owner/repo>` and commit both the folder
and the lock file. This supersedes the vendored-skills item in ADR 0001.

## Consequences

Every clone and every agent gets the same maintainer skills at the hash in
`skills-lock.json`. The cost is that `npx skills add ScaleDockHQ/better-supabase`
can list these skills next to the consumer skills in
`packages/better-supabase/skills`, so users may be offered skills meant for
maintainers. If that confuses users, move the maintainer skills to user-level
installs and restore the ignore rules.
