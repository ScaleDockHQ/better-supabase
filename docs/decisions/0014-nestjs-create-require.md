# 0014: Load `@nestjs/common` with a synchronous `createRequire`

- Status: accepted
- Date: 2026-10-09

## Context

Invariant 12 keeps imports at the top of the module and allows lazy loading
only for optional peers, through a dynamic `import()` with a variable
specifier. `@nestjs/common` is an optional peer of `better-supabase/nestjs`.
The adapter's `@Ctx()` parameter decorator calls `createParamDecorator`
while the controller class is being defined, which is synchronous: an
`await import()` cannot run there, and a top-level import would make every
app that installs better-supabase resolve NestJS.

## Decision

`src/nestjs/index.ts` loads `@nestjs/common` on first use with
`createRequire(import.meta.url)(NEST_COMMON)`, where `NEST_COMMON` is a
constant so bundlers leave the peer out. A missing package throws an error
that names the install command, and a loaded module without
`createParamDecorator` throws as well. The entry imports `node:module`, so
it is a Node-only entry in `NODE_ENTRIES`; NestJS runs on Node only.

## Alternatives considered

- A top-level `import` from `@nestjs/common`. Every consumer of the entry
  graph would need NestJS installed, against invariant 1.
- Make `@Ctx()` asynchronous or ask the app to pass
  `createParamDecorator`. Decorators cannot await, and passing the factory
  breaks the `@Ctx("db")` shape the docs and example use.
- A dynamic `import()` at module load with top-level `await`. It loads
  NestJS for every import of the entry, so a missing peer fails at import
  time instead of on first use.

## Consequences

The adapter keeps the decorator API NestJS users expect and adds no
required dependency. It is the one synchronous lazy load in the library;
invariant 12 lists it with the other exceptions. If NestJS ships an ESM
build that `import()` can load before decorators run, or a decorator API
that accepts a promise, this exception goes away.
