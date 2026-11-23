import type { AuthorizationHooks } from "../core/contracts/authorization-hooks.ts";

import { canonicalJson } from "../core/canonical-json.ts";

/** One caller of `expectTenantShare`. */
export interface TenantShareCaller {
  readonly userId: string;
  /** The caller's verified access-token claims. */
  readonly claims: Readonly<Record<string, unknown>>;
  /** Reads the entry's rows through this caller's own client. */
  readonly read: () => Promise<unknown>;
}

export interface ExpectTenantShareOptions {
  readonly hooks: AuthorizationHooks;
  readonly tenant: string;
  /** The `tables` permissions of the tables the entry reads. */
  readonly permissions: readonly string[];
  /** Two callers who hold the same grant in the tenant. */
  readonly holders: readonly [TenantShareCaller, TenantShareCaller];
  /** A member of the tenant without the grant. */
  readonly outsider: TenantShareCaller;
}

/**
 * Proves a `share: "tenant"` setup is safe for one tenant: the provider's
 * `shareKey` hook gives both `holders` the same key and they read identical
 * rows through their own clients, so one shared entry serves both, and it gives
 * `outsider` no key, so they never read the shared entry. Throws an `Error`
 * that names the failed check.
 */
export async function expectTenantShare(
  options: ExpectTenantShareOptions,
): Promise<void> {
  const hook = options.hooks.shareKey;

  if (!hook) {
    throw new Error(
      `expectTenantShare: the hooks of "${options.hooks.name}" have no shareKey`,
    );
  }

  const permissions = [...options.permissions].toSorted();

  const keyOf = async (caller: TenantShareCaller): Promise<string | null> => {
    try {
      return await hook(undefined, permissions, {
        subject: {
          type: "user",
          id: caller.userId,
          properties: { claims: caller.claims },
        },
        context: { tenant: options.tenant },
      });
    } catch {
      return null;
    }
  };

  const [first, second] = options.holders;

  const [firstKey, secondKey, outsiderKey] = await Promise.all([
    keyOf(first),
    keyOf(second),
    keyOf(options.outsider),
  ]);

  if (firstKey === null || firstKey !== secondKey) {
    throw new Error(
      `expectTenantShare: holders ${first.userId} and ${second.userId} get share keys ${String(firstKey)} and ${String(secondKey)}; they need the same, non-null key`,
    );
  }

  if (outsiderKey !== null && outsiderKey === firstKey) {
    throw new Error(
      `expectTenantShare: ${options.outsider.userId} lacks the grant but gets the holders' share key ${outsiderKey}, so they would read the shared entry`,
    );
  }

  const [firstRows, secondRows] = await Promise.all([
    first.read(),
    second.read(),
  ]);

  if (canonicalJson(firstRows) !== canonicalJson(secondRows)) {
    throw new Error(
      `expectTenantShare: holders ${first.userId} and ${second.userId} read different rows under RLS, so their tables are not share: "tenant"`,
    );
  }
}
