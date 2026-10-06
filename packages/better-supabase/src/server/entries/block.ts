import { defineMiddleware, type SingleKeyEntry } from "@supabase/middleware";

/**
 * Entry contributing `ctx[key]`: a block service built from the keys the
 * entries before it contribute, such as `ctx.postgresAdmin` from
 * `withPostgresAdminClient` after `withBetterSupabase`. The service is built
 * per request, on the pipeline's one Postgres pool, and runs under every
 * framework bridge.
 *
 * ```ts
 * pipeline(
 *   [withBetterSupabase(bs), withPostgresAdminClient(), withBlock('jobs', (ctx) => createJobs(ctx.postgresAdmin, queues))],
 *   (req, ctx) => ctx.jobs.drainRoute({ secret, handlers })(req),
 * )
 * ```
 */
export function withBlock<const Key extends string, In extends object, Service>(
  key: Key,
  create: (ctx: In) => Service,
): SingleKeyEntry<Key, In, Service> {
  return defineMiddleware<Key, undefined, In, Service>({
    key,
    run: () => (_request, ctx) =>
      // SAFETY: a computed key widens to string; the object has exactly `key`.
      Promise.resolve({ [key]: create(ctx) } as { [K in Key]: Service }),
  })();
}
