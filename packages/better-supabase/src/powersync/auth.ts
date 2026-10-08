import type { AuthSnapshot } from "../client/bind.ts";

/** The part of a PowerSync database `syncWithAuth` drives. */
export interface SyncedDatabaseLike<C> {
  connect(connector: C): Promise<void>;
  disconnect(): Promise<void>;
  disconnectAndClear(): Promise<void>;
}

/** `bs.auth` from a browser or native client. */
export interface AuthSourceLike {
  readonly current: () => AuthSnapshot;
  readonly subscribe: (listener: () => void) => () => void;
}

export interface SyncWithAuthOptions<C> {
  /** The connector, e.g. `createUploadConnector(...)`. */
  readonly connector: C;
  /**
   * Clears the local database on sign-out and when another user signs in,
   * so one user never reads another's rows. Unsynced changes are lost.
   * Defaults to true.
   */
  readonly clearOnSignOut?: boolean;
  /** Called after each connect, disconnect or clear fails. */
  readonly onError?: (cause: unknown) => void;
}

/**
 * Syncs while a user is signed in: connects on sign-in, and on sign-out
 * (or a different user) disconnects and clears the local database. An app
 * that starts signed out clears it too, since the rows may belong to a user
 * whose session ended while the app was closed. Steps
 * run one at a time in order. Returns a function that stops following the
 * session and disconnects.
 *
 * ```ts
 * useEffect(() => syncWithAuth(powersync, bs.auth, { connector }), []);
 * ```
 */
export function syncWithAuth<C>(
  db: SyncedDatabaseLike<C>,
  auth: AuthSourceLike,
  options: SyncWithAuthOptions<C>,
): () => void {
  const clear = options.clearOnSignOut ?? true;
  // undefined until the first settled snapshot: rows on disk may be anyone's.
  let user: string | null | undefined;
  let stopped = false;
  let queue: Promise<void> = Promise.resolve();
  const enqueue = (step: () => Promise<void>) => {
    queue = queue.then(step).catch((cause: unknown) => {
      options.onError?.(cause);
    });
  };
  const leave = () => (clear ? db.disconnectAndClear() : db.disconnect());

  const follow = () => {
    if (stopped) return;
    const snapshot = auth.current();
    if (snapshot.status === "loading") return;
    const next = snapshot.status === "signed-in" ? snapshot.user.id : null;
    if (next === user) return;
    const previous = user;
    user = next;
    if (previous === undefined ? next === null && clear : previous !== null)
      enqueue(leave);
    if (next !== null) enqueue(() => db.connect(options.connector));
  };

  follow();
  const unsubscribe = auth.subscribe(follow);
  return () => {
    stopped = true;
    unsubscribe();
    enqueue(() => db.disconnect());
  };
}
