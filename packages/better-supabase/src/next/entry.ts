import { cacheLife, cacheTag } from "next/cache.js";

import type { AuthState } from "../auth/resolve.ts";
import type { AuthSession } from "../auth/view.ts";
import type { CacheScope, CachedOptions } from "./types.ts";

import { tagFor } from "../core/tags.ts";
import { cachedLife, sessionIdTag, supportTag, tableTags } from "./cache.ts";

/** What `applyCacheEntry` reads from the scope's context. */
export interface CacheEntryScope<C, P> {
  readonly ctx: {
    readonly auth: AuthState<C, P>;
    readonly support?: { readonly session: { readonly id: string } } | null;
  };
  readonly view: AuthSession<C, P>;
  readonly scope: CacheScope;
  readonly tenant: string | undefined;
  readonly entry: CachedOptions;
  readonly userTags: (userId: string) => readonly string[];
  readonly warn: ((message: string) => void) | undefined;
}

/**
 * Frames of Next.js's cache wrapper, one per `"use cache"` function on the
 * stack.
 */
const CACHE_WRAPPER = /use-cache-wrapper/g;

let warnedNested = false;

/**
 * Best effort, development only: a second cache wrapper frame on the async
 * stack means this scope runs inside another one (see BS610). The stack format
 * is Next.js's, so a build that names its frames differently stays quiet.
 */
export function warnIfNested(
  warn: (message: string) => void,
  stack: string | undefined = new Error("scope").stack,
): void {
  if (warnedNested || (stack?.match(CACHE_WRAPPER)?.length ?? 0) < 2) {
    return;
  }

  warnedNested = true;
  warn(
    "bsb.cached() ran inside another cache scope. Private scopes don't nest and each one resolves the session again: call the inner function from the page, or pass the same bsb.sessionHandle() to both.",
  );
}

/** Sets `cacheLife` and the session, support, table and row tags of an entry. */
export function applyCacheEntry<C, P>(input: CacheEntryScope<C, P>): void {
  const { ctx, view, scope, tenant, entry } = input;

  if (input.warn) {
    warnIfNested(input.warn);
  }

  cacheLife(
    cachedLife(view, scope, entry.life, input.warn ? { warn: input.warn } : {}),
  );

  const tables = entry.tables ?? [];
  const first = tables[0];

  const claimed =
    ctx.auth.kind === "user" ? ctx.auth.claims["session_id"] : undefined;

  const sessionId = typeof claimed === "string" ? claimed : undefined;

  const tags = [
    ...(view.kind === "user" ? input.userTags(view.user.id) : []),
    ...(sessionId === undefined ? [] : [sessionIdTag(sessionId)]),
    ...(ctx.support ? [supportTag(ctx.support.session.id)] : []),
    ...(entry.tags ?? []),
    ...tables.flatMap((table) =>
      tableTags(table, tenant === undefined ? {} : { tenant }),
    ),
    ...(first !== undefined && entry.id !== undefined
      ? [tagFor(first, entry.id)]
      : []),
  ];

  if (tags.length > 0) {
    cacheTag(...tags);
  }
}
