# 0343: Taint tokens and server contexts

- Status: accepted
- Date: 2026-11-07
- Amends: 0316

## Context

The data transfer rule (`bsb.user()` returns four plain fields) keeps tokens out
of Client Components by convention. A page that passes a context or a token
across the boundary by mistake leaks it.

## Decision

`src/next/taint.ts` calls React's `experimental_taintUniqueValue` and
`experimental_taintObjectReference` through a namespace import, guarded by a
check that each function exists, because stable React builds omit them and
`next.config` only enables them with `experimental.taint`. `incomingAt` taints
the resolved auth state, its access token and the request's refresh token (read
with `readSession`, lifetime: the auth state); `scopedAt` taints the context;
`bsb.admin()` taints the context it returns. `createNextConfig()` sets the flag.

## Consequences

The Supabase clients a context creates are not tainted: `server/` entries import
no React, and the clients are created lazily inside them. The proof in
`tests/next/taint.test.ts` mocks React's taint functions and checks what they are
called with; the React taint error itself needs the Flight renderer and is
exercised by the example's build, not by a unit test.
