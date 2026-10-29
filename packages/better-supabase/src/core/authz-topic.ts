/**
 * The private Realtime topic the sessions module's `authzVersions` option
 * broadcasts on for servers. Only the service role reads it.
 */
export const AUTHZ_TOPIC = "better_supabase:authz";

/** The broadcast event both authorization topics use. */
export const AUTHZ_EVENT = "changed";

/**
 * Where a client learns the signed-in user's authorization version. The default
 * reads `api.caller_authz_version()` and listens on `authz:<uid>`; an
 * authorization library can pass its own (another topic, a push channel).
 */
export interface AuthzVersionSource {
  /** The live version, or `undefined` when it can't be read now. */
  current(): Promise<number | undefined>;
  /** Calls `listener` with each version it hears; returns the cleanup. */
  subscribe(listener: (version: number) => void): () => void;
}

/** The private topic a signed-in user reads their own version changes on. */
export function authzUserTopic(userId: string): string {
  return `authz:${userId}`;
}
