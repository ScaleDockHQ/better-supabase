# 0055: Connect PermDock Cloud on the Create page

Status: accepted

## Context

ADR 0039 lets the Create page name PermDock as one optional authorization
choice. A visitor who picks it still copies project details by hand.

## Decision

The marketing site connects a visitor's PermDock Cloud account with OAuth
and PKCE, as a public client at `https://permdock.com/api`, next to the
Supabase connection. The routes live under `/create/permdock` (`connect`,
`callback`, `disconnect`, `projects`) and reuse the sealed-cookie helpers of
`better-supabase/create/supabase`. The scopes are `projects:read` and
`policy:read`. Two env keys switch it on: `PERMDOCK_OAUTH_CLIENT_ID` and
`PERMDOCK_OAUTH_COOKIE_SECRET`. Without both, every route answers 404.

The library takes no new dependency and names nothing: only the marketing
routes, their session helper and env keys join the allowlist of
`check:no-permdock`.

## Consequences

The authorize, token and projects paths follow PermDock's OAuth contract and
are covered only by the 404 check until a maintainer sets the keys. The Vercel
environments need both keys.
