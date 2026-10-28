import type { Bootstrap } from "better-supabase/next";

import "server-only";

import { bsb } from "@/lib/supabase/server";

export const ISLAND_TABLES = [
  "customers",
  "notes",
  "contacts",
  "tags",
  "tasks",
] as const;

export type IslandTable = (typeof ISLAND_TABLES)[number];

/** What `public.island_counts` returns through `bootstrap_islands`. */
export type IslandCounts = Readonly<Record<IslandTable, number>>;

/** `?scope=remote` reads through `"use cache: remote"`; the default is private. */
export type IslandScope = "private" | "remote";

/** The ten islands' data as plain values, safe across a cache boundary. */
export interface Islands {
  readonly userId: string | null;
  readonly email: string | null;
  readonly organizationId: string | null;
  /** Seconds since epoch. */
  readonly expiresAt: number | null;
  /** Seconds since epoch. */
  readonly issuedAt: number | null;
  readonly authzVersion: number | null;
  /** `null` signed out or once `session_active()` is false. */
  readonly counts: IslandCounts | null;
  /** Whether the caller may add customers, from `getAccess`. */
  readonly canWrite: boolean;
  /** When the entry was computed, so a remote hit shows the first render's time. */
  readonly cachedAt: string;
}

/**
 * Every island calls this. The `bootstrap_islands` call runs once per request:
 * React's `cache()` inside `bsb.bootstrap` dedupes it, and the token verifies
 * once because the session memo keys on its hash.
 */
async function getIslands(): Promise<Islands> {
  "use cache: private";

  const boot = await bsb.bootstrap<IslandCounts>({
    rpc: "islands",
    tables: ISLAND_TABLES,
  });

  const access = await bsb.getAccess(boot);

  return islandsFrom(boot, await access.can("customers.write"));
}

/**
 * The same read in the remote scope: one entry per Auth session, shared by
 * every server instance behind `cacheHandlers.remote`. The token never keys
 * it.
 */
const getRemoteIslands = bsb.remote(async (key): Promise<Islands> => {
  "use cache: remote";

  const boot = await bsb.bootstrap<IslandCounts>({
    rpc: "islands",
    scope: "remote",
    key,
    tables: ISLAND_TABLES,
  });

  const access = await bsb.getAccess(boot, { key });

  return islandsFrom(boot, await access.can("customers.write"));
});

export function getIslandsIn(scope: IslandScope): Promise<Islands> {
  return scope === "remote" ? getRemoteIslands() : getIslands();
}

export function islandScope(value: string | string[] | undefined): IslandScope {
  return value === "remote" ? "remote" : "private";
}

function islandsFrom(
  boot: Bootstrap<unknown, unknown, IslandCounts>,
  canWrite: boolean,
): Islands {
  const { session } = boot;
  const user = session.kind === "user" ? session : null;

  return {
    userId: user?.user.id ?? null,
    email: user?.user.email ?? null,
    organizationId: boot.tenant,
    expiresAt: user?.expiresAt ?? null,
    issuedAt: user?.issuedAt ?? null,
    authzVersion: boot.authzVersion,
    counts: boot.sessionActive ? boot.data : null,
    canWrite,
    cachedAt: new Date().toISOString(),
  };
}
