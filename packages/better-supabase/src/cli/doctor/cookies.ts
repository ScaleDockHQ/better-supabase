import { walk } from "oxc-walker";

import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { lineColumn, parseSource } from "../config-document/parse.ts";
import { literal } from "./live.ts";

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
  /** The line of the first `auth.getSession()` call. */
  readonly getSessionLine: number | undefined;
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
  let getSessionLine: number | undefined;

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
        node.type === "CallExpression" &&
        node.callee.type === "MemberExpression" &&
        !node.callee.computed &&
        node.callee.property.type === "Identifier" &&
        node.callee.property.name === "getSession" &&
        node.callee.object.type === "MemberExpression" &&
        !node.callee.object.computed &&
        node.callee.object.property.type === "Identifier" &&
        node.callee.object.property.name === "auth"
      ) {
        getSessionLine ??= lineColumn(text, node.start).line;
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

  return { browser, server, tokensOnlyLine, getSessionLine };
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
interface SideFile {
  readonly file: DoctorContext["sources"][number];
  readonly side: CookieSide;
  readonly tokensOnly: boolean;
  readonly line: number | undefined;
  readonly getSessionLine: number | undefined;
}

function sideFiles(context: DoctorContext): SideFile[] {
  return context.sources.flatMap((file) => {
    const facts = cookieFacts(file.text);
    const side = cookieSide(facts);

    return side
      ? [
          {
            file,
            side,
            tokensOnly: facts.tokensOnlyLine !== undefined,
            line: facts.tokensOnlyLine,
            getSessionLine: facts.getSessionLine,
          },
        ]
      : [];
  });
}

function encodingDrift(context: DoctorContext): FindingInput[] {
  const sides = sideFiles(context);

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

/**
 * The bytes the user object of `userId` takes in the session cookie: the JSON
 * auth-js stores, base64 encoded. `undefined` when there is no such user.
 */
async function userObjectBytes(
  context: DoctorContext,
  userId: string,
): Promise<number | undefined | { readonly skipped: string }> {
  const db = context.database;

  if (!db || "skipped" in db) {
    return {
      skipped: db
        ? db.skipped
        : "it needs a database connection (local stack, $DATABASE_URL, $SUPABASE_DB_URL or --db-url-stdin)",
    };
  }

  const [row] = await db.query<{ bytes: number | string | null }>(
    `select octet_length(jsonb_build_object(
        'id', u.id, 'aud', u.aud, 'role', u.role, 'email', u.email,
        'email_confirmed_at', u.email_confirmed_at, 'phone', u.phone,
        'confirmed_at', u.confirmed_at, 'last_sign_in_at', u.last_sign_in_at,
        'app_metadata', u.raw_app_meta_data, 'user_metadata', u.raw_user_meta_data,
        'identities', coalesce((
          select jsonb_agg(jsonb_build_object(
            'identity_id', i.id, 'id', i.provider_id, 'user_id', i.user_id,
            'identity_data', i.identity_data, 'provider', i.provider,
            'last_sign_in_at', i.last_sign_in_at, 'created_at', i.created_at,
            'updated_at', i.updated_at, 'email', i.email))
          from auth.identities i where i.user_id = u.id), '[]'::jsonb),
        'created_at', u.created_at, 'updated_at', u.updated_at,
        'is_anonymous', u.is_anonymous)::text) as bytes
      from auth.users u where u.id = ${literal(userId)}::uuid`,
  );

  return row?.bytes === null || row?.bytes === undefined
    ? undefined
    : Math.ceil((Number(row.bytes) * 4) / 3);
}

/**
 * Neither side of the session cookie sets `tokens-only`, so every request
 * carries the user object (BS644).
 */
async function userInCookie(context: DoctorContext): Promise<FindingInput[]> {
  const sides = sideFiles(context);

  if (sides.length === 0 || sides.some((entry) => entry.tokensOnly)) {
    return [];
  }

  const [first] = sides;

  if (!first) {
    return [];
  }

  const readers = sides.filter(
    (entry) => entry.side === "server" && entry.getSessionLine !== undefined,
  );

  const sizes =
    context.hookUser === undefined
      ? undefined
      : await userObjectBytes(context, context.hookUser);

  let measured = "";

  if (typeof sizes === "number") {
    measured = ` For ${context.hookUser ?? ""} the user object takes about ${String(sizes)} bytes of the cookie.`;
  } else if (sizes === undefined && context.hookUser !== undefined) {
    measured = ` --as ${context.hookUser}: no such user in auth.users.`;
  } else if (sizes !== undefined) {
    measured = ` Measuring the user object for --as ${context.hookUser ?? ""} was skipped: ${sizes.skipped}.`;
  }

  const moving =
    readers.length === 0
      ? ""
      : ` Before switching, move the user reads in ${readers.map((entry) => `${entry.file.path}:${String(entry.getSessionLine ?? 1)}`).join(", ")} from \`auth.getSession()\` to \`bsb.claims()\`.`;

  return [
    {
      message: `The session cookie carries the user object, because neither the browser client nor the server sets \`tokens-only\` (${sides.map((entry) => entry.file.path).join(", ")}). Set \`cookies: { encode: 'tokens-only' }\` in \`createClient\` and \`auth: { cookie: { encode: 'tokens-only' } }\` in the server options to keep it out.${measured}${moving}`,
      target: "session-cookie:encode",
      location: { file: first.file.path, line: 1 },
    },
  ];
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
  {
    code: "BS644",
    severity: "info",
    title: "Session cookie carries the user object",
    description:
      "With the default `user-and-tokens`, `@supabase/ssr` writes the user object (often a third of the session JSON) into the cookie, so every request carries it. `tokens-only` on both sides keeps the access and refresh tokens alone, and the server reads the user from the verified token. With `--as`, the finding adds the bytes that user's object takes.",
    check: userInCookie,
  },
];
