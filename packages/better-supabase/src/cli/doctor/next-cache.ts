import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { CLIENT_BARREL_RULES } from "./client-barrels.ts";
import { lineOf } from "./shared.ts";

/** The `next.config` file names Next.js loads, in its order. */
export const NEXT_CONFIG_FILES = [
  "next.config.ts",
  "next.config.mts",
  "next.config.mjs",
  "next.config.js",
] as const;

/** Files whose presence means the app deploys to Vercel. */
export const VERCEL_FILES = [
  "vercel.ts",
  "vercel.json",
  ".vercel/project.json",
] as const;

/** A remote cache scope that `bsb.cached()` or `bsb.bootstrap()` reads. */
const REMOTE_SCOPE =
  /\bbsb\.remote\s*\(|\bscope\s*:\s*["'`]remote["'`]|["'`]use cache: remote["'`]/;

/** `cacheHandlers.remote`, or `createNextConfig`'s `remoteCacheHandler`. */
const REMOTE_HANDLER =
  /\bremoteCacheHandler\s*:|\bcacheHandlers\s*:\s*\{[^}]*\bremote\s*:/s;

/**
 * `'use cache: remote'` entries without a remote handler outside Vercel
 * (BS608): Next.js keeps them in each instance's memory, so every instance and
 * every deploy misses on its own.
 */
function remoteWithoutHandler(context: DoctorContext): FindingInput[] {
  if (context.vercel === true) {
    return [];
  }

  const config: TextFile | undefined = context.nextConfig;

  if (config && REMOTE_HANDLER.test(config.text)) {
    return [];
  }

  const file = context.sources.find((source) => REMOTE_SCOPE.test(source.text));

  if (!file) {
    return [];
  }

  return [
    {
      message: `${file.path} caches in the remote scope, but ${config?.path ?? "next.config"} sets no remote cache handler and the app doesn't deploy to Vercel. Each instance then keeps its own in-memory copy. Set \`remoteCacheHandler\` in createNextConfig (or \`cacheHandlers.remote\`) to a shared handler such as Redis.`,
      target: `${file.path}:remote`,
      location: { file: file.path, line: lineOf(file.text, REMOTE_SCOPE) ?? 1 },
    },
  ];
}

/** A function whose first statement is the `"use cache: private"` directive. */
const PRIVATE_FUNCTION =
  /(?:function\s+(\w+)\s*\([^)]*\)[^{=]*|(?:const|let)\s+(\w+)\s*=\s*(?:async\s*)?(?:function\s*)?\([^)]*\)[^{=]*(?:=>)?\s*)\{\s*["']use cache: private["']/g;

interface PrivateFunction {
  readonly name: string;
  readonly file: string;
  readonly text: string;
  readonly body: string;
  readonly index: number;
}

/** The text of the `{ ... }` block that opens at `open`. */
function blockAt(text: string, open: number): string {
  let depth = 0;

  for (let index = open; index < text.length; index += 1) {
    const char = text.charAt(index);

    if (char === "{") {
      depth += 1;
    } else if (char === "}") {
      depth -= 1;

      if (depth === 0) {
        return text.slice(open, index + 1);
      }
    }
  }

  return text.slice(open);
}

function privateFunctions(sources: readonly TextFile[]): PrivateFunction[] {
  return sources.flatMap((source) =>
    [...source.text.matchAll(PRIVATE_FUNCTION)].flatMap((match) => {
      const name = match[1] ?? match[2];

      return name === undefined
        ? []
        : [
            {
              name,
              file: source.path,
              text: source.text,
              body: blockAt(
                source.text,
                match.index + match[0].lastIndexOf("{"),
              ),
              index: match.index,
            },
          ];
    }),
  );
}

/**
 * A `"use cache: private"` function that calls another one (BS610): Next.js
 * doesn't allow private scopes inside each other, and each one resolves the
 * session again. Read in the outer function and pass the values down, or hand
 * every scope `bsb.sessionHandle()`.
 */
function nestedPrivateScopes(context: DoctorContext): FindingInput[] {
  const functions = privateFunctions(context.sources);
  const names = new Set(functions.map((fn) => fn.name));

  return functions.flatMap((outer) =>
    [...names]
      .filter(
        (name) =>
          name !== outer.name &&
          new RegExp(`\\b${name}\\s*\\(`).test(outer.body),
      )
      .map((inner) => ({
        message: `${outer.file}: ${outer.name} runs in \`"use cache: private"\` and calls ${inner}, which has the same directive. Private cache scopes can't nest, and each one resolves the session again. Call ${inner} from the page and pass its result down, or read both in one scope.`,
        target: `${outer.file}:${outer.name}:${inner}`,
        location: {
          file: outer.file,
          line: outer.text.slice(0, outer.index).split("\n").length,
        },
      })),
  );
}

/** A service-role client built inside a function body. */
const ADMIN_CALL = /\bbsb\.admin\s*\(|\bcreateAdminClient\s*\(/;

/**
 * A `"use cache: private"` function that uses the service role (BS611): the
 * private scope exists to keep per-user data, and an admin client reads past
 * the user's policies, so what it returns is cached under the user's key but
 * isn't theirs. Read as the user, or move the admin read out of the scope.
 */
function adminInPrivateScope(context: DoctorContext): FindingInput[] {
  return privateFunctions(context.sources).flatMap((fn) =>
    ADMIN_CALL.test(fn.body)
      ? [
          {
            message: `${fn.file}: ${fn.name} runs in \`"use cache: private"\` and builds an admin client. The service role skips the user's policies, so its result doesn't belong in a per-user scope and each call costs an extra verification. Read as the user, or move the admin read out of the cached function.`,
            target: `${fn.file}:${fn.name}`,
            location: {
              file: fn.file,
              line: fn.text.slice(0, fn.index).split("\n").length,
            },
          },
        ]
      : [],
  );
}

export const NEXT_CACHE_RULES: readonly Rule[] = [
  {
    code: "BS608",
    severity: "warning",
    title: "Remote cache scope without a remote cache handler",
    description:
      "`bsb.remote()` and `bsb.cached({ scope: \"remote\" })` run in `'use cache: remote'`. Vercel provides a shared remote handler; elsewhere Next.js falls back to an in-memory one per instance, so entries are never shared and every deploy starts cold. Set `cacheHandlers.remote` (`remoteCacheHandler` in `createNextConfig`).",
    check: remoteWithoutHandler,
  },
  {
    code: "BS610",
    severity: "warning",
    title: "Nested private cache scopes",
    description:
      'A function with `"use cache: private"` calls another function with the same directive. Next.js doesn\'t nest private scopes, and each scope resolves the session again. Call the inner function from the page, or read both in one scope.',
    check: nestedPrivateScopes,
  },
  {
    code: "BS611",
    severity: "warning",
    title: "Service-role client in a private cache scope",
    description:
      "A function with `\"use cache: private\"` calls `bsb.admin()` or `createAdminClient`. The service role ignores the user's policies, so the cached result is not the user's data. Read as the user, or move the admin read out of the scope.",
    check: adminInPrivateScope,
  },
  ...CLIENT_BARREL_RULES,
];
