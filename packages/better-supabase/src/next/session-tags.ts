import type { SessionSnapshot } from "../auth/snapshot.ts";
import type { AuthorizationHooks } from "../core/contracts/authorization-hooks.ts";

import { invalidateAll, sessionIdTag, sessionTag } from "./cache.ts";

/** The user's session tag and the authorization provider's tags for them. */
export function userSessionTags(
  hooks: AuthorizationHooks | undefined,
  userId: string,
): readonly string[] {
  return [sessionTag(userId), ...(hooks?.sessionTags?.(userId) ?? [])];
}

/**
 * Drops the caller's own cached entries and evicts them from the version cache.
 * Only the caller's verified snapshot decides whose, so the action is safe to
 * expose.
 */
export async function refreshCallerCache(
  snapshot: SessionSnapshot | null,
  server: {
    readonly authorization: AuthorizationHooks | undefined;
    evictSession(userId: string): Promise<void>;
  },
): Promise<void> {
  if (!snapshot) {
    return;
  }

  invalidateAll([
    ...userSessionTags(server.authorization, snapshot.userId),
    ...(snapshot.sessionId === null ? [] : [sessionIdTag(snapshot.sessionId)]),
  ]);
  await server.evictSession(snapshot.userId);
}
