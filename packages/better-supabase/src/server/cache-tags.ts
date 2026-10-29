import type { AuthorizationHooks } from "../core/contracts/authorization-hooks.ts";
import type { TagOptions } from "../core/tags.ts";

import { tagFor } from "../core/tags.ts";

/** The tag cached entries of a user carry. */
export function sessionTag(userId: string): string {
  return `bsb:session:${userId}`;
}

/** The user's session tag and the authorization provider's tags for them. */
export function userSessionTags(
  hooks: AuthorizationHooks | undefined,
  userId: string,
): readonly string[] {
  return [sessionTag(userId), ...(hooks?.sessionTags?.(userId) ?? [])];
}

/**
 * The tag the cached entries of one Auth session carry
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
