import type { DbError } from "../core/errors.ts";

import { sharedReader } from "../server/tenant-share.ts";

/** What `inTenantFill` returns: the body's value and the first refused read. */
export interface TenantFillResult<T> {
  readonly value: T;
  /** Set when a read left the entry's tables: the fill would not be stored. */
  readonly refused: DbError | undefined;
}

/**
 * Runs `body` with the context a `share: "tenant"` fill of `bsb.kept()` or
 * `bsb.remote()` hands it: `ctx.db` reads only `tables`, and `shareGuard(ctx,
 * db)` gates a db the app builds itself. Use it to test an app's own services
 * under the table guard without a Next.js request.
 */
export async function inTenantFill<Ctx extends object, T>(
  ctx: Ctx,
  tables: readonly string[],
  body: (ctx: Ctx) => PromiseLike<T>,
): Promise<TenantFillResult<T>> {
  const reader = sharedReader(ctx, tables);
  const value = await body(reader.ctx);

  return { value, refused: reader.guard.refused() };
}
