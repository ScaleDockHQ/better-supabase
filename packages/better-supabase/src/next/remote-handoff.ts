import type { SessionSnapshot } from "../auth/snapshot.ts";
import type { RemoteCacheKey } from "./types.ts";

interface Handoff {
  snapshot: SessionSnapshot;
  count: number;
}

const HANDOFFS = Symbol.for("better-supabase.remote-handoffs");

/**
 * The handoff slot, on `globalThis` so the proxy's and the render's module
 * graphs share it.
 */
function handoffs(): Map<string, Handoff> {
  // SAFETY: HANDOFFS is a module symbol, so nothing else writes to that global slot.
  const scope = globalThis as { [HANDOFFS]?: Map<string, Handoff> };

  scope[HANDOFFS] ??= new Map<string, Handoff>();

  return scope[HANDOFFS];
}

/**
 * The handoff entry for a key. It holds only what the key parts name, so a
 * token registered under it belongs to that user and session.
 */
export function handoffKey(key: RemoteCacheKey): string {
  const owner =
    key.shared === null
      ? `${key.userId ?? "-"}:${key.sessionId ?? "*"}:${String(key.authzVersion ?? 0)}`
      : `key:${key.shared}`;

  return key.support === null ? owner : `${owner}:support:${key.support}`;
}

/**
 * Registers the caller's verified snapshot for one call and returns its
 * release. Concurrent calls under one key count up, so the first to finish
 * leaves the token for the others.
 */
export function handOff<C>(
  key: RemoteCacheKey,
  snapshot: SessionSnapshot<C>,
): () => void {
  const slot = handoffKey(key);
  const map = handoffs();
  const entry = map.get(slot);

  if (entry) {
    entry.count += 1;
    entry.snapshot = snapshot;
  } else {
    map.set(slot, { snapshot, count: 1 });
  }

  let released = false;

  return () => {
    if (released) {
      return;
    }

    released = true;
    const current = map.get(slot);

    if (current) {
      current.count -= 1;

      if (current.count <= 0) {
        map.delete(slot);
      }
    }
  };
}

/** The snapshot a running call registered under the key. */
export function takeHandoff<C>(
  key: RemoteCacheKey,
): SessionSnapshot<C> | undefined {
  // SAFETY: handOff stored the SessionSnapshot<C> of the server that reads it back.
  return handoffs().get(handoffKey(key))?.snapshot as
    | SessionSnapshot<C>
    | undefined;
}
