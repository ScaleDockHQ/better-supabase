# 0840: Serve Next.js build files cache first from a bounded cache that deploys keep

- Status: accepted
- Date: 2026-11-13

## Context

The Next.js example worker and the worker that `init` writes served every
`/_next/static` URL cache first, in the same cache as the offline shell. Neither
cache was ever trimmed, so each deploy added its chunks for good. The rule also
matched `/_next/static/service-worker/`, which Next.js 16.4 serves at a stable URL
with `max-age=0, must-revalidate`, so a worker compiled there could stay stale.

Every other file under `/_next/static` is immutable per URL: a content hash, a
build ID or a `?dpl=` deployment token. `next start` and Vercel send
`public, max-age=31536000, immutable` for them. A shell rendered offline, cached
or prefetched, needs the chunks it names, and the HTTP cache is not a guarantee.
A tab on the previous build still asks for that build's chunks after a deploy.

## Decision

Both workers keep cache first for `/_next/static` and change four things:

- They skip `/_next/static/service-worker/`.
- They store a response only when it is a same-origin `200` whose
  `Cache-Control` includes `immutable`.
- Build files live in their own cache (`acme-next-static-v1` in the example,
  `next-static-v1` from `init`), trimmed to 512 entries, oldest first, and
  dropped when the origin is out of quota.
- Activation deletes only unknown cache names, so a deploy never clears the
  build cache. The suffix changes only when the matching rule changes.

The files are `apps/examples/nextjs/public/sw.js`, the `public/sw.js` template in
`packages/better-supabase/src/cli/templates-next.ts`, its fixture, and the
Offline and PWA docs page.

## Alternatives considered

Network only for `/_next/static` leaves offline shells to the HTTP cache, which
browsers evict. Stale-while-revalidate or network first revalidate URLs that
never change. Clearing the build cache on every activation breaks open tabs on
the previous build. A cache name per deploy needs the worker to change on every
deploy, which a hand-written worker does not.

## Consequences

The cache stays bounded however often the app deploys, and offline shells keep
their chunks. Trimming is first in, first out rather than least recently used,
which is enough for a cap this size. Revisit this if Next.js changes which
`/_next/static` paths it marks immutable.
