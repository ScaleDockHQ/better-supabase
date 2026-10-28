/**
 * The 0.35 auth changes: the proxy refreshes on every request it matches
 * (parallel requests share one token refresh), session cookies are written by
 * `@supabase/ssr`, and the old cookie codec and prefetch predicates are gone.
 * In the blocks, `transition()` takes its reason in an options object and
 * `validateGraph` takes the step library as `{ steps }`.
 */

import type { Codemod, ReviewLine } from "./codemod.ts";

import { codeRanges } from "./code-ranges.ts";

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly text: string;
}

const POLICY = /(?<![\w$])(refresh|verifySession)(\s*:\s*)(["'])navigation\3/g;

const SESSION_PROMISE = /(?<![\w$.])sessionPromise(?=\s*=\s*\{)/g;

const SUPABASE_FOR = /(?<=\.\s*)supabaseFor(?=\s*\()/g;

// `.transition(subject, to, "reason")`, where the reason is a string literal.
const TRANSITION_REASON =
  /(\.\s*transition\s*\(\s*(?:\{[^(){}]*\}|[^(),{}]+),\s*[^(),{}]+,\s*)((["'`])(?:\\.|(?!\3)[^\\])*\3)(\s*,?\s*\))/g;

// `validateGraph(graph, steps)`, where the library isn't an object literal.
const VALIDATE_GRAPH =
  /(?<![\w$.])(validateGraph\s*\(\s*[^(),{}]+,\s*)([\w$.]+)(\s*,?\s*\))/g;

/**
 * `refresh: "navigation"` is `refresh: true`, `verifySession: "navigation"` is
 * `verifySession: "document"`, `<SessionProvider sessionPromise={...}>` is
 * `session={...}` and `server.supabaseFor(auth)` is
 * `server.contextClient(auth)`, where the key is code.
 */
function renamePolicies(text: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const ranges = codeRanges(text);

  const inCode = (match: RegExpMatchArray): boolean =>
    ranges.some(
      ([start, end]) =>
        match.index !== undefined && match.index >= start && match.index < end,
    );

  const edits: Edit[] = [
    ...[...text.matchAll(POLICY)]
      .filter(inCode)
      .map((match) => ({
        start: match.index,
        end: match.index + match[0].length,
        text: `${match[1]}${match[2]}${
          match[1] === "refresh" ? "true" : `${match[3]}document${match[3]}`
        }`,
      })),
    ...[...text.matchAll(SESSION_PROMISE)]
      .filter(inCode)
      .map((match) => ({
        start: match.index,
        end: match.index + match[0].length,
        text: "session",
      })),
    ...[...text.matchAll(SUPABASE_FOR)]
      .filter(inCode)
      .map((match) => ({
        start: match.index,
        end: match.index + match[0].length,
        text: "contextClient",
      })),
    ...[...text.matchAll(TRANSITION_REASON)]
      .filter(inCode)
      .map((match) => ({
        start: match.index,
        end: match.index + match[0].length,
        text: `${match[1]}{ reason: ${match[2]} })`,
      })),
    ...[...text.matchAll(VALIDATE_GRAPH)]
      .filter(inCode)
      .map((match) => ({
        start: match.index,
        end: match.index + match[0].length,
        text: `${match[1]}{ ${match[2] === "steps" ? "steps" : `steps: ${match[2]}`} })`,
      })),
  ];

  let result = text;

  for (const edit of edits.toSorted((a, b) => b.start - a.start)) {
    result = result.slice(0, edit.start) + edit.text + result.slice(edit.end);
  }

  return { text: result, review: [] };
}

export const CODEMOD_0_35: Codemod = {
  name: "0.35",
  description:
    'Rewrites refresh: "navigation" to refresh: true, verifySession: "navigation" to verifySession: "document" and the SessionProvider sessionPromise prop to session, supabaseFor calls to contextClient, a string reason passed to transition() to { reason } and validateGraph(graph, steps) to validateGraph(graph, { steps }), and lists for review the lines that use onExpiredPrefetch, shouldRefresh, clearSessionCookies (now async), the removed cookie codec (writeSession, refreshSession, AUTH_CACHE_HEADERS, pruneSessionChunks, sessionEncoding, clearSessionAtScopes), sessionStale, life.min and life.max, contextFromSession with a token, a destructured supabaseFor, sessions: false, a transition() reason that is not a string literal, memory forget (now a soft delete) and maps keyed by WorkflowNodeKind',
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
    {
      pattern: /\bsessionStatusRoute\(/,
      message:
        "`sessionStatusRoute` reads the verified claims only now (`verifySession` defaults to false): pass `verifySession: true` to keep asking Auth on every check",
    },
    {
      pattern: /(?<![\w$.])supabaseFor\b/,
      message:
        "`supabaseFor` on the server is now `contextClient`: rename the destructured method and its calls",
    },
    {
      pattern: /\bsessions\s*:\s*false\b/,
      message:
        "`sessions: false` now turns off the one verified-token memo, so every request verifies its token again (about 0.1 ms each): drop it unless you need that",
    },
    {
      pattern:
        /\.transition\s*\(\s*(?:\{[^(){}]*\}|[^(),{}]+),\s*[^(),{}]+,\s*(?![\s{"'`])[^)]/,
      message:
        "`transition(subject, to, reason)` takes `{ reason, actor }` as its third argument now: pass `{ reason }`",
    },
    {
      pattern: /\barchival\s*\.\s*forget\s*\(/,
      message:
        "`memory.archival.forget` soft deletes now: `restore` brings the memory back, and `purge` (service role, on a schedule) removes it for good",
    },
    {
      pattern: /\bRecord<\s*WorkflowNodeKind\b/,
      message:
        "`WorkflowNodeKind` takes the app's own kinds now (any string): key a map of every kind by `WorkflowBuiltinNodeKind`, with a fallback for custom kinds",
    },
  ],
  source: renamePolicies,
};
