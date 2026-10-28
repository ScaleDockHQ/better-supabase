/**
 * The 0.35 auth changes: the proxy refreshes on every request it matches
 * (parallel requests share one token refresh), session cookies are written by
 * `@supabase/ssr`, and the old cookie codec and prefetch predicates are gone.
 */

import type { Codemod, ReviewLine } from "./codemod.ts";

import { codeRanges } from "./code-ranges.ts";

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly text: string;
}

const POLICY = /(?<![\w$])(refresh|verifySession)(\s*:\s*)(["'])navigation\3/g;

/**
 * `refresh: "navigation"` is `refresh: true`, and `verifySession: "navigation"`
 * is `verifySession: "document"`, where the key is code.
 */
function renamePolicies(text: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const ranges = codeRanges(text);

  const edits: Edit[] = [...text.matchAll(POLICY)]
    .filter((match) =>
      ranges.some(([start, end]) => match.index >= start && match.index < end),
    )
    .map((match) => ({
      start: match.index,
      end: match.index + match[0].length,
      text: `${match[1]}${match[2]}${
        match[1] === "refresh" ? "true" : `${match[3]}document${match[3]}`
      }`,
    }));

  let result = text;

  for (const edit of edits.toSorted((a, b) => b.start - a.start)) {
    result = result.slice(0, edit.start) + edit.text + result.slice(edit.end);
  }

  return { text: result, review: [] };
}

export const CODEMOD_0_35: Codemod = {
  name: "0.35",
  description:
    'Rewrites refresh: "navigation" to refresh: true and verifySession: "navigation" to verifySession: "document", and lists for review the lines that use onExpiredPrefetch, shouldRefresh, clearSessionCookies (now async), the removed cookie codec (writeSession, refreshSession, AUTH_CACHE_HEADERS, pruneSessionChunks, sessionEncoding, clearSessionAtScopes), sessionStale, life.min and life.max, and contextFromSession with a token',
  review: [
    {
      pattern: /\bonExpiredPrefetch\b/,
      message:
        "`onExpiredPrefetch` is gone: the proxy refreshes prefetches too, so remove the option",
    },
    {
      pattern:
        /\bshouldRefresh\b|\bshouldCheckSession\b.*better-supabase\/server/,
      message:
        "`shouldRefresh` and the `better-supabase/server` `shouldCheckSession` are gone: every request may refresh, since parallel requests share one token refresh. Use `isDocumentLoad` or `isPrefetch` from `better-supabase/server` to tell requests apart (`better-supabase/next` keeps `shouldCheckSession`)",
    },
    {
      pattern: /\bclearSessionCookies\(/,
      message:
        "`clearSessionCookies()` returns a promise now (it clears through `@supabase/ssr`): await it",
    },
    {
      pattern:
        /\b(?:writeSession|refreshSession|AUTH_CACHE_HEADERS|pruneSessionChunks|sessionEncoding|clearSessionAtScopes|DEFAULT_SESSION_ENCODING)\b/,
      message:
        "The cookie codec exports are gone from `better-supabase/server` and `better-supabase/ssr`: let `resolveAuth` refresh and `clearSessionCookies` clear, or use `createServerClient` from `@supabase/ssr` directly",
    },
    {
      pattern: /\b(?:sessionStale|SessionStaleOptions)\b/,
      message:
        "`sessionStale` is gone: `bsb.cached()` sets `stale` to 300 seconds, so call it in the scope instead of `cacheLife({ stale: sessionStale(session) })`, and pass `life: { capToToken: true }` to keep the old cap at the token's lifetime",
    },
    {
      pattern: /\blife\s*:\s*\{[^}]*\b(?:min|max)\s*:/,
      message:
        "`life.min` and `life.max` are gone: `life.stale` sets the stale time (default 300), and `capToToken: true` caps it at the token's lifetime",
    },
    {
      pattern: /\bcontextFromSession\([^)]*\{\s*token\b/,
      message:
        "`contextFromSession(session, { token })` is gone: pass the `SessionSnapshot` from `bsb.getClaims()`, which builds the context without verifying again",
    },
  ],
  source: renamePolicies,
};
