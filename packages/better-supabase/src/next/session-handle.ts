import { after } from "next/server.js";

import type { SessionSnapshot } from "../auth/snapshot.ts";
import type { CacheShare, RemoteCacheKey } from "./types.ts";

import { handOff } from "./remote-handoff.ts";

/** What a caller needs to name the key of its session. */
export interface KeyParts<C> {
  readonly userId: string | null;
  readonly tenant: string | undefined;
  readonly support: string | null;
  readonly snapshot: SessionSnapshot<C> | null;
  readonly share: CacheShare<C>;
}

/**
 * The serializable key of a session or a shared entry. The token is never a
 * part, so a rotation keeps the entries keyed by it.
 */
export function cacheKeyOf<C>(parts: KeyParts<C>): RemoteCacheKey {
  const { share, snapshot } = parts;
  const shared = typeof share === "object" ? share.key(snapshot) : null;

  return {
    userId: shared === null ? parts.userId : null,
    sessionId:
      shared === null && share === "session"
        ? (snapshot?.sessionId ?? null)
        : null,
    tenant: parts.tenant ?? null,
    authzVersion: shared === null ? (snapshot?.authzVersion ?? null) : null,
    shared,
    support: parts.support,
  };
}

/**
 * Parks a snapshot under its handle until the response is sent. Outside a
 * request scope `after()` throws; the snapshot is released at once and scopes
 * read the request's own session instead.
 */
export function parkUntilResponseEnds<C>(
  handle: RemoteCacheKey,
  snapshot: SessionSnapshot<C> | null,
): void {
  if (!snapshot) {
    return;
  }

  const release = handOff(handle, snapshot);

  try {
    after(release);
  } catch {
    release();
  }
}
