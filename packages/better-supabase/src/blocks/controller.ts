import type { ClientAuth } from "../client/bind.ts";

/**
 * A block's client state, framework-agnostic. `subscribe` and `getSnapshot`
 * follow the external-store contract, so React's `useSyncExternalStore`,
 * a Vue `shallowRef` or a Svelte store wrap it in a few lines.
 */
export interface Controller<S, A> {
  /**
   * Adds a listener. The first one starts the controller's work (loads,
   * realtime, shortcuts) and the last one to leave stops it.
   */
  readonly subscribe: (listener: () => void) => () => void;
  /** The current state; the same object until it changes. */
  readonly getSnapshot: () => S;
  readonly actions: A;
  /** Stops the work and drops every listener; the controller stays idle after it. */
  readonly dispose: () => void;
}

/** The session a controller follows: `bs.auth` from `createClient()`. */
export type AuthPort = Pick<ClientAuth, "current" | "subscribe">;

export interface ControllerState<S> {
  readonly get: () => S;
  /** Merges `patch` into the state; listeners hear of it only when a value changed. */
  readonly set: (patch: Partial<S> | ((current: S) => Partial<S>)) => void;
  /**
   * The current run: it changes when the controller starts or stops, so an
   * answer that arrives after a restart is dropped with `run !== state.run()`.
   */
  readonly run: () => number;
}

export interface ControllerParts<A> {
  readonly actions: A;
  /** Runs when the first listener subscribes; returns the cleanup. */
  readonly start?: () => (() => void) | undefined;
}

/** Builds a controller from its initial state, its actions and its work. */
export function defineController<S extends object, A>(
  initial: S,
  build: (state: ControllerState<S>) => ControllerParts<A>,
): Controller<S, A> {
  let snapshot = initial;
  let run = 0;
  let stop: (() => void) | undefined;
  let disposed = false;
  const listeners = new Set<() => void>();
  const state: ControllerState<S> = {
    get: () => snapshot,
    set: (patch) => {
      const changes = typeof patch === "function" ? patch(snapshot) : patch;
      const current = new Map<string, unknown>(Object.entries(snapshot));
      const changed = Object.entries(changes).some(
        ([key, value]) => !Object.is(current.get(key), value),
      );
      if (!changed) {
        return;
      }
      snapshot = { ...snapshot, ...changes };
      for (const listener of [...listeners]) {
        listener();
      }
    },
    run: () => run,
  };
  const parts = build(state);
  const halt = (): void => {
    run += 1;
    const cleanup = stop;
    stop = undefined;
    cleanup?.();
  };
  return {
    subscribe: (listener) => {
      if (disposed) {
        return () => undefined;
      }
      listeners.add(listener);
      if (listeners.size === 1) {
        run += 1;
        stop = parts.start?.();
      }
      return () => {
        if (!listeners.delete(listener) || listeners.size > 0) {
          return;
        }
        halt();
      };
    },
    getSnapshot: () => snapshot,
    actions: parts.actions,
    dispose: () => {
      if (disposed) {
        return;
      }
      disposed = true;
      listeners.clear();
      halt();
    },
  };
}

/**
 * Runs `effect` for the signed-in user, and again after its cleanup when
 * another user signs in. Nothing runs while the session loads or is signed
 * out. Returns the function that stops following the session.
 */
export function whileSignedIn(
  auth: AuthPort,
  effect: (userId: string) => (() => void) | undefined,
): () => void {
  let user: string | null = null;
  let cleanup: (() => void) | undefined;
  const sync = (): void => {
    const snapshot = auth.current();
    const next = snapshot.status === "signed-in" ? snapshot.user.id : null;
    if (next === user) {
      return;
    }
    cleanup?.();
    cleanup = undefined;
    user = next;
    if (next !== null) {
      cleanup = effect(next);
    }
  };
  const unsubscribe = auth.subscribe(sync);
  sync();
  return () => {
    unsubscribe();
    cleanup?.();
    cleanup = undefined;
    user = null;
  };
}
