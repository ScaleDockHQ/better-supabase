# 1258. Tree-shaken resource and sign-in flows

Date: 2026-11-26

## Status

Accepted

## Context

`createNext` returned an object that carried every flow as a member, so an app that
only read data still shipped the resource routes and the sign-in flows. Lazy
`import()` would drop them but is limited to optional peers (invariant 12).

## Decision

`createNext` stores a symbol-keyed host member (`RESOURCES_HOST`, `AUTH_FLOWS_HOST`)
and each flow lives on its own subpath, where a function reads the host:
`createResources(bsb)` from `better-supabase/next/resources` and
`createAuthFlows(bsb)` from `better-supabase/next/sign-in`. Static imports stay at the
top, and a bundler drops what the app never imports.

## Consequences

The shipped `createNext member` consumer fell from about 94.6 KB to about 89.9 KB
gzip after the resources move, and the sign-in move lowers it further. The
`bsb.resources(...)` and `bsb.signIn*` members are removed (changeset lists the
old-to-new table). Support and record helpers stay on `bsb`.
