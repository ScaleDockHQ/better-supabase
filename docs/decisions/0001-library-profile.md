# 0001: Follow the library profile of the repo standard

- Status: accepted
- Date: 2026-09-30

## Context

The repo standard describes a product monorepo: an app, an API and an MCP app
on top of shared `domain`, `contract`, `services`, `policy`, `ai`, `email` and
`ui` packages, with i18n, multi-tenancy and billing. better-supabase is a
published npm library. Its surfaces are the package and its CLI, the docs site
and the marketing site. The local Supabase stack is a test fixture, not a
product database.

## Decision

The repo follows the standard's toolchain, lint, format, TypeScript, test,
hook, release, CI, editor, Portless and docs sections as written. These parts
do not apply, and the repo does not add them:

- Sections 3 and 4: the product `app`, `api` and `mcp` apps, and the
  `domain`, `contract`, `services`, `policy`, `ai`, `email` and `ui` packages.
  The OpenAPI snapshot and Problem Details for a product API go with them.
- Section 6: `packages/ai`. The only AI feature is Ask AI in the docs, which
  calls the AI Gateway from one route handler.
- Sections 8, 10 and 11: i18n, multi-tenancy, PermDock, Stripe, the audit log
  and the Supabase OAuth server. The fixture schema has tenants and RBAC
  because the library supports them, not because the repo is multi-tenant.
- Sentry and Resend. Docs and marketing are static sites that send no email.
- Vendored skills. The repo ships its own consumer skills, and `.agents/skills`
  is a discovery root for `npx skills add`, so it stays empty. There is no
  `skills-lock.json` and no `.cursorignore`.
- The `dev:oauth`, `email:dev` and `openapi:generate` scripts, and the i18n
  item in the pull request checklist.

## Consequences

The "When you change X" table in `AGENTS.md` has library rows (subpaths,
exports, doctor findings, SQL kit modules) instead of the product rows for
contract procedures, permissions and i18n copy. If the repo gains a product
app, revisit this record and add the missing sections.
