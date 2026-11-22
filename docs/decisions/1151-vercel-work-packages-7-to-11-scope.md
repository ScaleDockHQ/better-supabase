# 1151: Vercel work packages 7 to 11: what shipped and what did not

- Status: accepted
- Date: 2026-11-21

## Context

Packages 7 to 11 of the Vercel plan were checked against the installed
packages and the sources before building. This amends ADR 0850 where the plan
disagreed with them.

## Decision

Shipped: `onVerdict` and `firewallRateLimiter` in `vercel-security`;
`getDeadline` and `deadlineMargin` for the Postgres pool; Blob `ttlDays`,
`cacheControlMaxAge`, `storeId`, `oidcToken` and the full error-class map; the
domains DNS check through `getDomainConfig`; `bsb.caller` for SvelteKit remote
functions; `bsb.guard` for TanStack Start function middleware.

Dropped because the plan was wrong:

- Next `deploymentId`: Vercel sets `NEXT_DEPLOYMENT_ID` itself and a mismatch
  throws, so `createNextConfig` must not set it.
- Signed URLs in the image loader: a loader returns a URL and can't sign, and
  the token already covers its transform.
- A doctor rule for drops and renames: `migration-safety.ts` already has it.

Not built in this change, to be planned separately: Blob upload-completed
handlers, wildcard domains, the Postgres Next `cacheHandlers`, a Nitro entry,
a Nuxt module, the Astro route cache and session driver, the AI SDK surfaces
(package 8) and the agent docs in the package (package 11: version-matched
docs, the `init` AGENTS.md block, the published skills and the Vercel MCP
recipe). None was confirmed against live docs in this pass.

## Alternatives considered

Building the unconfirmed items from the plan's wording. Rejected: the plan
marks them "confirm first".

## Consequences

The shipped items are small additions to existing entries, so no new subpath
or size baseline changed.
