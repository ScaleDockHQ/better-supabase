import { revalidateTag, updateTag } from "next/cache.js";

import type { AuthSession } from "../auth/view.ts";
import type { CacheAdapter } from "../core/cache.ts";
import type { TagOptions } from "../core/tags.ts";
import type {
  CacheScope,
  CachedLife,
  NextCacheOptions,
  RevalidateProfile,
} from "./types.ts";

import { cacheTagsOf, tagFor } from "../core/tags.ts";

/** The tag `bsb.cached()` adds to entries rendered in a support session. */
export function supportTag(sessionId: string): string {
  return `bsb:support:${sessionId}`;
}

/** The shortest time the Next.js client router keeps a prefetched entry. */
const MIN_CLIENT_STALE = 30;

/** The shortest `stale` a private entry needs to ride in the App Shell. */
const APP_SHELL_STALE = 300;

/** `"use cache: remote"` lifetimes when `life` leaves them unset. */
const REMOTE_LIFE = { revalidate: 300, expire: 3600 } as const;

const warned = new Set<string>();

/** Logs `message` once per process. */
function warnOnce(warn: (message: string) => void, message: string): void {
  if (!warned.has(message)) {
    warned.add(message);
    warn(message);
  }
}

/**
 * Whether a refresh or a sign-in would change the view, so no shell may keep
 * it.
 */
function changesOnRefresh(session: AuthSession): boolean {
  return (
    session.kind === "invalid" ||
    (session.kind === "none" &&
      (session.reason === "expired" || session.reason === "refresh_failed"))
  );
}

/** Seconds left on the token, or `undefined` for a view without one. */
function tokenSecondsLeft(
  session: AuthSession,
  now: number,
): number | undefined {
  return session.kind === "user" && session.expiresAt !== null
    ? session.expiresAt - Math.floor(now / 1000)
    : undefined;
}

/**
 * The `cacheLife` of a `bsb.cached()` entry. `stale` is `life.stale`, else 300
 * seconds, so the entry rides in the App Shell; the token's lifetime caps it
 * only with `capToToken`, because the proxy refreshes prefetches and the
 * session tags are evicted on sign-out. A view that a refresh would change (an
 * `expired` or `refresh_failed` cookie, an `invalid` token) is 0. Remote
 * entries default to `revalidate` 300 and `expire` 3600. In development a
 * `stale` below 300 warns that the entry leaves the App Shell, and below 30
 * that it leaves the prerender.
 */
export function cachedLife(
  session: AuthSession,
  scope: CacheScope,
  life: CachedLife = {},
  options: {
    readonly now?: number;
    readonly warn?: (message: string) => void;
  } = {},
): { stale: number; revalidate?: number; expire?: number } {
  const { warn } = options;

  if (warn && life.stale !== undefined && life.stale < APP_SHELL_STALE) {
    warnOnce(
      warn,
      life.stale < MIN_CLIENT_STALE
        ? `bsb.cached(): life.stale ${String(life.stale)} is below 30 seconds, so the entry leaves the prerender and renders on every request`
        : `bsb.cached(): life.stale ${String(life.stale)} is below 300 seconds, so the entry leaves the App Shell and instant navigations wait for it`,
    );
  }

  let stale = changesOnRefresh(session) ? 0 : (life.stale ?? APP_SHELL_STALE);

  const left = life.capToToken
    ? tokenSecondsLeft(session, options.now ?? Date.now())
    : undefined;

  if (left !== undefined) {
    stale = left < MIN_CLIENT_STALE ? 0 : Math.min(stale, left);
  }

  const revalidate =
    life.revalidate ??
    (scope === "remote" ? REMOTE_LIFE.revalidate : undefined);

  const expire =
    life.expire ?? (scope === "remote" ? REMOTE_LIFE.expire : undefined);

  return {
    stale,
    ...(revalidate === undefined ? {} : { revalidate }),
    ...(expire === undefined ? {} : { expire }),
  };
}

/** The tag `bsb.cached()` puts on a user's entries. */
export function sessionTag(userId: string): string {
  return `bsb:session:${userId}`;
}

/**
 * The tag `bsb.cached()` puts on the entries of one Auth session
 * (`SessionSnapshot.sessionId`): invalidate it to drop one device's entries.
 */
export function sessionIdTag(sessionId: string): string {
  return `bsb:session-id:${sessionId}`;
}

/**
 * The table tags of a read: the tenant's and every tenant's, or the table's. A
 * read across tenants (`"*"`) also carries the table's, which every mutation
 * invalidates, including one scoped to a single tenant.
 */
export function tableTags(table: string, options: TagOptions): string[] {
  if (options.tenant === "*") {
    return [tagFor(table), tagFor(table, undefined, options)];
  }

  return options.tenant === undefined
    ? [tagFor(table)]
    : [
        tagFor(table, undefined, options),
        tagFor(table, undefined, { tenant: "*" }),
      ];
}

/** The next read waits for fresh data instead of serving the stale entry. */
const EXPIRE_NOW = { expire: 0 } as const;

/**
 * Invalidates tags with `updateTag` (Server Actions), else `revalidateTag`
 * (Route Handlers), else not at all (jobs, scripts). The first tag decides for
 * the rest, so a mutation outside an action throws once, not per tag.
 */
export function invalidateAll(
  tags: readonly string[],
  profile: RevalidateProfile = EXPIRE_NOW,
): void {
  let index = 0;

  try {
    for (; index < tags.length; index += 1) {
      updateTag(tags[index]!);
    }

    return;
  } catch {
    // Not in a Server Action: revalidate from the tag that failed.
  }

  try {
    for (; index < tags.length; index += 1) {
      revalidateTag(tags[index]!, profile);
    }
  } catch {
    // Outside a Next.js request (jobs, scripts): nothing to invalidate.
  }
}

/**
 * Invalidates `bsb:<table>` for every table in the target, the tenant's
 * `bsb:<table>@<tenant>` (every tenant's `bsb:<table>@*` when the mutation has
 * no tenant) and `bsb:<table>:<id>` for the changed rows. Reads another tenant
 * tagged stay cached. `createNext` attaches it unless `cacheTags: false`.
 */
export function nextCache(options: NextCacheOptions = {}): CacheAdapter {
  return {
    name: "next",
    invalidate: (target) => {
      invalidateAll(cacheTagsOf(target), options.revalidate);
    },
  };
}

/**
 * Event hubs that already invalidate Next.js cache tags. Every instance a
 * definition derives shares its hub, and `createNext` can run again for one
 * definition (hot reload, a definition in another package), so tags are
 * invalidated once per mutation.
 */
export const nextCacheAttached: WeakSet<object> = new WeakSet<object>();
