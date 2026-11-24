import type { SessionSnapshot } from "../auth/snapshot.ts";
import type { AuthSession } from "../auth/view.ts";
import type { DbError } from "../core/errors.ts";
import type { SchemaMeta } from "../schema/types.ts";
import type { TenantShare } from "../server/tenant-share.ts";
import type { RemoteCacheKey, RemoteOptions } from "./types.ts";

import { tablesWithFunctions } from "../server/tenant-share.ts";
import { cacheKeyOf } from "./session-handle.ts";

interface RemoteKeyInput<Ctx, C, P> {
  readonly ctx: Ctx & {
    readonly support?: { readonly session: { readonly id: string } } | null;
  };
  readonly view: AuthSession<C, P>;
  readonly snapshot: SessionSnapshot<C> | null;
  readonly tenant: string | undefined;
  readonly options: Pick<RemoteOptions<C>, "functions" | "share" | "tables">;
  readonly meta: SchemaMeta | undefined;
  readonly tenantShare: (
    ctx: Ctx,
    tables: readonly string[],
    tenant: string | undefined,
    functions?: readonly string[],
  ) => Promise<TenantShare>;
  readonly onRefused: (error: DbError) => void;
}

/**
 * The key `bsb.remote()` hands its function: per session by default, per user
 * or per tenant grant when `share` asks and the tables allow it. A shared key
 * names the tables and functions its scope may read.
 */
export async function remoteKeyOf<Ctx, C, P>(
  input: RemoteKeyInput<Ctx, C, P>,
): Promise<RemoteCacheKey> {
  const { ctx, view, options } = input;
  const asked = options.share ?? "session";
  const functions = options.functions ?? [];

  const tables = tablesWithFunctions(
    input.meta,
    options.tables ?? [],
    functions,
  );

  const decided =
    asked === "tenant" && !ctx.support
      ? await input.tenantShare(ctx, tables, input.tenant, functions)
      : undefined;

  const shared = decided?.kind === "shared" ? decided.key : undefined;

  if (decided?.kind === "refused") {
    input.onRefused(decided.error);
  }

  const parts = cacheKeyOf({
    userId: view.kind === "user" ? view.user.id : null,
    tenant: input.tenant,
    support: ctx.support?.session.id ?? null,
    snapshot: input.snapshot,
    share:
      shared === undefined
        ? asked === "tenant"
          ? ctx.support
            ? "session"
            : "user"
          : asked
        : { key: () => `tenant:${shared}` },
  });

  return shared === undefined
    ? parts
    : { ...parts, tables, ...(functions.length > 0 ? { functions } : {}) };
}
