# 0057: Run Create in the cloud app

- Status: accepted
- Date: 2026-10-20

## Context

Create started as a page on the marketing site with no accounts and no
database of its own: designs ride on the URL (ADR 0040), Deploy to Supabase
keeps its tokens in a sealed cookie (ADR 0041), and the PermDock Cloud
connection does the same (ADR 0055). The better-supabase cloud app, at
`app.bettersupabase.com`, adds what those choices ruled out: an AI chat that
edits the design, saved projects with versions, designs too large for a
link, safe re-deploys with history, a hosted MCP server and teams. Running
two copies of the canvas would mean every Create change lands twice.

## Decision

Create lives only in the cloud app, at `https://app.bettersupabase.com/create`.
It stays public: the canvas, Get code and Deploy to Supabase need no account,
and signing in adds the paid features. The cloud app owns the Supabase and
PermDock OAuth apps, their routes and their env keys.

The marketing site keeps the docs and the docs MCP server at
`bettersupabase.com/mcp`. It removes `app/(create)`, `features/create`, the
Create helpers in `lib`, their tests and e2e specs, and the
`SUPABASE_OAUTH_*` and `PERMDOCK_OAUTH_*` keys from `apps/marketing/env.ts`,
`apps/marketing/turbo.json` and `.env.example`. `next.config.ts` redirects
`/create/:path*` to the app with a 308, and Next.js passes the query string
through, so shared links keep their preset and design. The navbar links
Create to the app and adds a Sign in button. `createUrl()` in
`better-supabase/preset` now returns the app URL; `presetOf` and `designOf`
read a code from either host.

This supersedes the hosting parts of ADR 0040, 0041 and 0055. Their formats
and flows stand: the `&design=` code, the PKCE authorization code flow and the
sealed cookies, now served by the cloud app.

## Alternatives considered

- Keep Create on marketing and send only signed-in visitors to the app. Two
  canvases drift, and a visitor loses their design at the hand-off.
- Proxy `/create` on marketing to the app with a rewrite. The OAuth callbacks,
  cookies and Supabase Auth session would all span two hosts.

## Consequences

The library repo no longer runs Create, so a Create change ships from the
cloud repo, and the library's Create e2e coverage moves there. The cloud app
must stay on a design format at least as new as the published library, or
`decodeDesign` rejects newer codes. `check:no-permdock` drops its marketing
exceptions, because no marketing file names the PermDock option any more.
