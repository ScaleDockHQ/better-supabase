---
"better-supabase": minor
---

Add adapters for more server frameworks, all typed structurally:

- `better-supabase/node`: `toNodeHandler` for `node:http`, `toExpress`, `toFastify` and `toKoa`, with route guards and a Problem Details error handler for each. The `IncomingMessage` to `Request` helpers (`toWebRequest`, `sendWebResponse`) are exported too.
- `better-supabase/nestjs`: `toNestMiddleware`, a `guard()` for `@UseGuards`, `problemFilter()` and the `@Ctx()` parameter decorator. `@nestjs/common` is an optional peer, loaded on first use.
- `better-supabase/astro`: `createAstro` with `onRequest` middleware, `guard`, `require` and an Actions `action` wrapper, plus `createImageService` for Storage image transformations.
- `better-supabase/h3/v1` for Nitro 2 and `better-supabase/nuxt`, a Nuxt module that registers the entries as server middleware and auto-imports the Vue composables.
- `better-supabase/solid-start`: `createSolidStart` with middleware, `require` and `action` for server functions.

`storageImageUrl()` in `better-supabase/storage` renders public Storage objects at a size; `createImageLoader` in `better-supabase/next/image` now uses it. Every guard, `require` and action also takes `roles` and `roleClaim` to admit only callers with a role.
