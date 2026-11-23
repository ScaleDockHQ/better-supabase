import { walk } from "oxc-walker";

import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { lineColumn, parseSource } from "../config-document/parse.ts";

/**
 * Specifiers that import the browser client, which writes the session cookie in
 * the browser.
 */
const BROWSER_MODULES: ReadonlySet<string> = new Set([
  "better-supabase/client",
]);

/** Specifiers that read or refresh the session cookie on the server. */
const SERVER_MODULES: ReadonlySet<string> = new Set([
  "better-supabase/server",
  "better-supabase/next",
  "better-supabase/ssr",
  "better-supabase/hono",
  "better-supabase/orpc",
  "better-supabase/edge",
  "better-supabase/expo",
]);

type CookieSide = "browser" | "server";

/** What the syntax tree of a file says about the session cookie. */
interface CookieFacts {
  readonly browser: boolean;
  readonly server: boolean;
  /** The line of the first `encode: "tokens-only"` property. */
  readonly tokensOnlyLine: number | undefined;
}

/**
 * Reads the imports that name a client, the `createBrowserClient(` and
 * `createServerClient(` calls and the `encode: "tokens-only"` property from the
 * tree, so a comment, a string or a type annotation never counts.
 */
function cookieFacts(text: string): CookieFacts {
  let browser = false;
  let server = false;
  let tokensOnlyLine: number | undefined;

  const module = (source: string): void => {
    browser ||= BROWSER_MODULES.has(source);
    server ||= SERVER_MODULES.has(source);
  };

  walk(parseSource(text).program, {
    enter(node) {
      if (
        node.type === "ImportDeclaration" &&
        node.specifiers.length > 0 &&
        typeof node.source.value === "string"
      ) {
        module(node.source.value);
      } else if (
        (node.type === "ExportNamedDeclaration" ||
          node.type === "ExportAllDeclaration") &&
        node.source !== null &&
        typeof node.source.value === "string"
      ) {
        module(node.source.value);
      } else if (
        node.type === "CallExpression" &&
        node.callee.type === "Identifier"
      ) {
        browser ||= node.callee.name === "createBrowserClient";
        server ||= node.callee.name === "createServerClient";
      } else if (
        node.type === "Property" &&
        !node.computed &&
        ((node.key.type === "Identifier" && node.key.name === "encode") ||
          (node.key.type === "Literal" && node.key.value === "encode")) &&
        node.value.type === "Literal" &&
        node.value.value === "tokens-only"
      ) {
        tokensOnlyLine ??= lineColumn(text, node.start).line;
      }
    },
  });

  return { browser, server, tokensOnlyLine };
}

function cookieSide(facts: CookieFacts): CookieSide | undefined {
  if (facts.browser === facts.server) {
    return undefined;
  }

  return facts.browser ? "browser" : "server";
}

/**
 * Files on one side of the session cookie that set `encode: 'tokens-only'`
 * while files on the other side don't (BS412).
 */
function encodingDrift(context: DoctorContext): FindingInput[] {
  const sides = context.sources.flatMap((file) => {
    const facts = cookieFacts(file.text);
    const side = cookieSide(facts);

    return side
      ? [
          {
            file,
            side,
            tokensOnly: facts.tokensOnlyLine !== undefined,
            line: facts.tokensOnlyLine,
          },
        ]
      : [];
  });

  const tokensOnly = sides.filter((entry) => entry.tokensOnly);

  if (tokensOnly.length === 0) {
    return [];
  }

  const findings: FindingInput[] = [];

  for (const side of ["browser", "server"] as const) {
    const set = tokensOnly.find((entry) => entry.side === side);

    if (!set) {
      continue;
    }

    const other = side === "browser" ? "server" : "browser";

    const unset = sides.filter(
      (entry) => entry.side === other && !entry.tokensOnly,
    );

    if (unset.length === 0) {
      continue;
    }

    const line = set.line ?? 1;
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
