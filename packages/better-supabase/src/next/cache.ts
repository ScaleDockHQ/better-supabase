import { revalidateTag, updateTag } from "next/cache.js";

import type { AuthSession } from "../auth/view.ts";
import type { CacheAdapter } from "../core/cache.ts";
import type { TagOptions } from "../core/tags.ts";
import type {
  NextCacheOptions,
  RevalidateProfile,
  SessionStaleOptions,
} from "./types.ts";

import { cacheTagsOf, tagFor } from "../core/tags.ts";

/** The tag `bsb.cached()` adds to entries rendered in a support session. */
export function supportTag(sessionId: string): string {
  return `bsb:support:${sessionId}`;
}

/** The shortest time the Next.js client router keeps a prefetched entry. */
const MIN_CLIENT_STALE = 30;

/**
 * `cacheLife` `stale` seconds for a view of `session`: `max`, but never past
 * the token's expiry, and 0 once fewer than `min` seconds are left. A
 * signed-out view that a refresh would change (an `expired` or `refresh_failed`
 * cookie, or an `invalid` token) is 0 as well, so it never joins the App
 * Shell.
 */
export function sessionStale(
  session: AuthSession,
  options: SessionStaleOptions = {},
  now: number = Date.now(),
): number {
  const min = Math.max(MIN_CLIENT_STALE, options.min ?? MIN_CLIENT_STALE);
  const max = options.max ?? 300;

  switch (session.kind) {
    case "invalid": {
      return 0;
    }

    case "anon": {
      return session.reason === "expired" || session.reason === "refresh_failed"
        ? 0
        : max;
    }

    case "service":
    case "apiKey": {
      return max;
    }

    case "user": {
      if (session.expiresAt === null) {
        return max;
      }

      const remaining = session.expiresAt - Math.floor(now / 1000);

      return remaining < min ? 0 : Math.min(max, remaining);
    }

    default: {
      const exhaustive: never = session;

      return exhaustive;
    }
  }
}

/** The tag `bsb.cached()` puts on a user's entries. */
export function sessionTag(userId: string): string {
  return `bsb:session:${userId}`;
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
