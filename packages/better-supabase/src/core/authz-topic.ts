/**
 * The private Realtime topic the sessions module's `authzVersions` option
 * broadcasts on for servers. Only the service role reads it.
 */
export const AUTHZ_TOPIC = "better_supabase:authz";

/** The broadcast event both authorization topics use. */
export const AUTHZ_EVENT = "changed";

/** The private topic a signed-in user reads their own version changes on. */
export function authzUserTopic(userId: string): string {
  return `authz:${userId}`;
}
