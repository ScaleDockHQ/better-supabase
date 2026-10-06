import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { lineOf } from "./shared.ts";

const TOKENS_ONLY = /\bencode\s*:\s*["'`]tokens-only["'`]/;

/** Imports that create the browser client, which writes the session cookie in the browser. */
const BROWSER_SIDE =
  /from\s+["']better-supabase\/client["']|\bcreateBrowserClient\s*\(/;

/** Imports that read or refresh the session cookie on the server. */
const SERVER_SIDE =
  /from\s+["']better-supabase\/(?:server|next|ssr|hono|orpc|edge|expo)["']|\bcreateServerClient\s*\(/;

type CookieSide = "browser" | "server";

function cookieSide(file: TextFile): CookieSide | undefined {
  const browser = BROWSER_SIDE.test(file.text);
  const server = SERVER_SIDE.test(file.text);
  if (browser === server) return undefined;
  return browser ? "browser" : "server";
}

/**
 * Files on one side of the session cookie that set `encode: 'tokens-only'`
 * while files on the other side don't (BS412).
 */
function encodingDrift(context: DoctorContext): FindingInput[] {
  const sides = context.sources.flatMap((file) => {
    const side = cookieSide(file);
    return side
      ? [{ file, side, tokensOnly: TOKENS_ONLY.test(file.text) }]
      : [];
  });
  const tokensOnly = sides.filter((entry) => entry.tokensOnly);
  if (tokensOnly.length === 0) return [];
  const findings: FindingInput[] = [];
  for (const side of ["browser", "server"] as const) {
    const set = tokensOnly.find((entry) => entry.side === side);
    if (!set) continue;
    const other = side === "browser" ? "server" : "browser";
    const unset = sides.filter(
      (entry) => entry.side === other && !entry.tokensOnly,
    );
    if (unset.length === 0) continue;
    const line = lineOf(set.file.text, TOKENS_ONLY) ?? 1;
    findings.push({
      message: `${set.file.path} writes the session cookie with \`encode: 'tokens-only'\`, but the ${other} side (${unset.map((entry) => entry.file.path).join(", ")}) uses the default \`user-and-tokens\`. Set the same \`encode\` on both sides.`,
      target: `${set.file.path}:encode`,
      location: { file: set.file.path, line },
    });
  }
  return findings;
}

export const COOKIE_RULES: readonly Rule[] = [
  {
    code: "BS412",
    severity: "info",
    title: "Session cookie encoding differs between server and browser",
    description:
      "`@supabase/ssr` needs the same `cookies.encode` on the server and in the browser client. With `tokens-only` on one side only, the other side writes the user object back into the cookie, or reads a session without one and `session.user` throws.",
    check: encodingDrift,
  },
];
