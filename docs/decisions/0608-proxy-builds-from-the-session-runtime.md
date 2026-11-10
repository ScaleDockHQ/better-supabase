# 0608: Build the proxy from the session runtime

- Status: accepted
- Date: 2026-11-10

## Context

`createProxy` called `createServer`, so the `better-supabase/next/proxy` entry bundled the
server's clients, executors and query builder although the proxy only resolves a session and
seeds the verified-token memo. The shipped proxy was 64,832 bytes gzipped.

## Decision

`sessionsRuntime` in `server/sessions-runtime.ts` holds what the session side needs: the
environment, the JWKS prefetch, the verified-token memo and `resolve`. `createServer` and
`createProxy` both build from it, with the same default process memo and the same JWKS cache
(ADR 0116 and 0595), so a page and the proxy still share one verification. `createProxy` seeds
the memo through `serverSessions` and has no request context.

## Consequences

The shipped proxy is 47,740 bytes gzipped (raw 134,271 to 61,210). A bundle test asserts that
the proxy closure holds none of the server's actor header, delete-account call or PostgREST
builder. The remaining size is the token verification and cookie code in `resolve`, which the
proxy needs; the 30 KB target would need `resolveAuth` split further and is left open.
