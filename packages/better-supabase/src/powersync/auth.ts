import type { AuthSnapshot } from "../client/bind.ts";

import { authzVersionOf } from "../auth/snapshot.ts";
import { claimAt, tenantPathsFor } from "../core/claims.ts";

/** The part of a PowerSync database `syncWithAuth` drives. */
export interface SyncedDatabaseLike<C> {
  connect(connector: C): Promise<void>;
  disconnect(): Promise<void>;
  disconnectAndClear(): Promise<void>;
}

/** `bsb.auth` from a browser or native client. */
export interface AuthSourceLike {
  readonly current: () => AuthSnapshot;
  readonly subscribe: (listener: () => void) => () => void;
}

/** The claims of a signed-in user, as `bsb.auth` holds them. */
export type SyncClaims = Readonly<Record<string, unknown>>;

export interface SyncWithAuthOptions<C> {
  /** The connector, e.g. `createUploadConnector(...)`. */
  readonly connector: C;
  /**
   * Clears the local database on sign-out and when another user signs in, so
   * one user never reads another's rows. Unsynced changes are lost. Defaults to
   * true.
   */
  readonly clearOnSignOut?: boolean;
  /**
   * Where the active tenant is read from, for the default fingerprint: a claim
   * path or a list. Defaults to `tenant_id`, then `app_metadata.tenant_id`;
   * pass `config.claims.tenant` when the app renamed it.
   */
  readonly tenantClaim?: string | readonly string[];
  /**
   * What the sync service decides on. When it changes for the same user, the
   * database reconnects, so the service reads the new token and drops the rows
   * the user lost. Defaults to the user, the active tenant and `authz_ver`.
   */
  readonly fingerprint?: (claims: SyncClaims) => string;
  /** Called after each connect, disconnect or clear fails. */
  readonly onError?: (cause: unknown) => void;
}

/**
 * Stops following the session and disconnects. `reconnect()` reconnects with a
 * fresh token, for a change the token doesn't show yet.
 */
export interface AuthSync {
  (): void;
  /**
   * Disconnects and connects again while the same user is signed in, so the
   * connector fetches the token again. Calls made before it runs share one
   * reconnect; a sign-out or another user first skips it.
   */
  readonly reconnect: () => Promise<void>;
}

/**
 * The default fingerprint: user, active tenant and authorization version, the
 * claims sync rules usually decide on.
 */
export function claimsFingerprint(
  claims: SyncClaims,
  tenantClaim?: string | readonly string[],
): string {
  const sub = typeof claims["sub"] === "string" ? claims["sub"] : "";

  const tenant = tenantPathsFor(tenantClaim)
    .map((path) => claimAt(claims, path))
    .find((value) => value !== undefined);

  return JSON.stringify([sub, tenant ?? null, authzVersionOf(claims)]);
}

/**
 * Syncs while a user is signed in: connects on sign-in, and on sign-out (or a
 * different user) disconnects and clears the local database. An app that starts
 * signed out clears it too, since the rows may belong to a user whose session
 * ended while the app was closed. A token with another tenant or `authz_ver`
 * for the same user reconnects, so the sync service applies the new rules.
 * Steps run one at a time in order. Returns a function that stops following the
 * session and disconnects, with a `reconnect()` method.
 *
 * ```ts
 * useEffect(() => syncWithAuth(powersync, bsb.auth, { connector }), []);
 * ```
 */
export function syncWithAuth<C>(
  db: SyncedDatabaseLike<C>,
  auth: AuthSourceLike,
  options: SyncWithAuthOptions<C>,
): AuthSync {
  const clear = options.clearOnSignOut ?? true;

  const fingerprintOf =
    options.fingerprint ??
    ((claims: SyncClaims) => claimsFingerprint(claims, options.tenantClaim));

  // undefined until the first settled snapshot: rows on disk may be anyone's.
  let user: string | null | undefined;
  let fingerprint: string | undefined;
  let stopped = false;
  let queue: Promise<void> = Promise.resolve();
  let pending: Promise<void> | undefined;

  const enqueue = (step: () => Promise<void>): Promise<void> => {
    queue = queue.then(step).catch((cause: unknown) => {
      options.onError?.(cause);
    });

    return queue;
  };

  const leave = () => (clear ? db.disconnectAndClear() : db.disconnect());

  const reconnect = (): Promise<void> => {
    if (pending) {
      return pending;
    }

    const target = user;

    if (stopped || typeof target !== "string") {
      return queue;
    }

    const run = enqueue(async () => {
      pending = undefined;

      if (stopped || user !== target) {
        return;
      }

      await db.disconnect();
      await db.connect(options.connector);
    });

    pending = run;

    return run;
  };

  const follow = () => {
    if (stopped) {
      return;
    }

    const snapshot = auth.current();

    if (snapshot.status === "loading") {
      return;
    }

    const next = snapshot.status === "signed-in" ? snapshot.user.id : null;

    const print =
      snapshot.status === "signed-in" ? fingerprintOf(snapshot.claims) : "";

    if (next === user) {
      if (next !== null && print !== fingerprint) {
        fingerprint = print;
        void reconnect();
      }

      return;
    }

    const previous = user;
    user = next;
    fingerprint = print;
    pending = undefined;

    if (previous === undefined ? next === null && clear : previous !== null) {
      void enqueue(leave);
    }

    if (next !== null) {
      void enqueue(() => db.connect(options.connector));
    }
  };

  follow();
  const unsubscribe = auth.subscribe(follow);

  const stop = () => {
    stopped = true;
    unsubscribe();
    void enqueue(() => db.disconnect());
  };

  return Object.assign(stop, { reconnect });
}
