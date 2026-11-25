import type { Node, Program } from "oxc-parser";

import { walk } from "oxc-walker";

import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { lineColumn, parseSource } from "../config-document/parse.ts";
import { CLIENT_BARREL_RULES } from "./client-barrels.ts";
import { KEPT_EXPIRY_RULES } from "./kept-expiry.ts";
import { PROXY_SIZE_RULES } from "./proxy-size.ts";
import { PUBLIC_KEPT_RULES } from "./public-kept.ts";

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

/** The name a non-computed key or an identifier holds. */
function nameOf(node: Node): string | undefined {
  if (node.type === "Identifier") {
    return node.name;
  }

  return node.type === "Literal" && typeof node.value === "string"
    ? node.value
    : undefined;
}

/**
 * Whether `node` is the string `value`, written as a literal or a bare
 * template.
 */
function isString(node: Node, value: string): boolean {
  if (node.type === "Literal") {
    return node.value === value;
  }

  return (
    node.type === "TemplateLiteral" &&
    node.expressions.length === 0 &&
    node.quasis[0]?.value.cooked === value
  );
}

/** `object.property(` with both names plain identifiers. */
function isMemberCall(
  node: Node,
  object: string,
  ...properties: string[]
): boolean {
  return (
    node.type === "CallExpression" &&
    node.callee.type === "MemberExpression" &&
    !node.callee.computed &&
    node.callee.object.type === "Identifier" &&
    node.callee.object.name === object &&
    node.callee.property.type === "Identifier" &&
    properties.includes(node.callee.property.name)
  );
}

/** A call to the bare name `name(`, not `x.name(`. */
function isBareCall(node: Node, ...names: string[]): boolean {
  return (
    node.type === "CallExpression" &&
    node.callee.type === "Identifier" &&
    names.includes(node.callee.name)
  );
}

/** Walks `root` and returns the offset of the first node `match` accepts. */
function firstMatch(
  root: Node,
  match: (node: Node) => boolean,
): number | undefined {
  let found: number | undefined;

  walk(root, {
    enter(node) {
      if (found === undefined && match(node)) {
        found = node.start;
      }
    },
  });

  return found;
}

/** Where `bsb.remote()`, `scope: "remote"` or `"use cache: remote"` appears. */
function remoteScopeAt(program: Program): number | undefined {
  return firstMatch(
    program,
    (node) =>
      isMemberCall(node, "bsb", "remote") ||
      (node.type === "Property" &&
        !node.computed &&
        nameOf(node.key) === "scope" &&
        isString(node.value, "remote")) ||
      (node.type === "Literal" && node.value === "use cache: remote") ||
      (node.type === "TemplateLiteral" && isString(node, "use cache: remote")),
  );
}

/** `remoteCacheHandler: ...` or `cacheHandlers: { remote: ... }`. */
function hasRemoteHandler(program: Program): boolean {
  return (
    firstMatch(
      program,
      (node) =>
        node.type === "Property" &&
        !node.computed &&
        (nameOf(node.key) === "remoteCacheHandler" ||
          (nameOf(node.key) === "cacheHandlers" &&
            node.value.type === "ObjectExpression" &&
            node.value.properties.some(
              (property) =>
                property.type === "Property" &&
                !property.computed &&
                nameOf(property.key) === "remote",
            ))),
    ) !== undefined
  );
}

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

  if (config && hasRemoteHandler(parseSource(config.text).program)) {
    return [];
  }

  for (const file of context.sources) {
    const at = remoteScopeAt(parseSource(file.text).program);

    if (at !== undefined) {
      return [
        {
          message: `${file.path} caches in the remote scope, but ${config?.path ?? "next.config"} sets no remote cache handler and the app doesn't deploy to Vercel. Each instance then keeps its own in-memory copy. Set \`remoteCacheHandler\` in createNextConfig (or \`cacheHandlers.remote\`) to a shared handler such as Redis.`,
          target: `${file.path}:remote`,
          location: { file: file.path, line: lineColumn(file.text, at).line },
        },
      ];
    }
  }

  return [];
}

/** Where `next.config` turns on `durableUseCacheEntries`. */
function durableFlagAt(program: Program): number | undefined {
  return firstMatch(
    program,
    (node) =>
      node.type === "Property" &&
      !node.computed &&
      nameOf(node.key) === "durableUseCacheEntries" &&
      !(node.value.type === "Literal" && node.value.value === false),
  );
}

/**
 * `durableUseCacheEntries` with a shared reader (BS646): its entries outlive a
 * deploy, and their key holds neither the database's policies nor the Supabase
 * project.
 */
function durableSharedEntries(context: DoctorContext): FindingInput[] {
  const config = context.nextConfig;
  const flag = config && durableFlagAt(parseSource(config.text).program);

  if (!config || flag === undefined) {
    return [];
  }

  const reader = context.sources.find((file) => {
    const { program } = parseSource(file.text);

    return (
      remoteScopeAt(program) !== undefined ||
      firstMatch(program, (node) => isMemberCall(node, "bsb", "public")) !==
        undefined
    );
  });

  if (!reader) {
    return [];
  }

  return [
    {
      message: `${config.path} turns on \`experimental.durableUseCacheEntries\`, and ${reader.path} fills a shared entry (\`bsb.public()\` or a remote scope). Its key then follows your code and the generated schema, not the deploy: a migration that changes a policy or a function body without changing the generated files keeps the old entries, and so does a deployment that points at another Supabase project through the same cache handler. Expire the tables' tags after such a migration, give each Supabase project its own handler, or use \`bsb.kept()\` with a \`version\`.`,
      target: `${config.path}:durableUseCacheEntries`,
      location: { file: config.path, line: lineColumn(config.text, flag).line },
    },
  ];
}

interface DirectiveFunction {
  readonly name: string;
  readonly file: string;
  /** The function node, whose body the rules read. */
  readonly body: Node;
  /** The line of the declaration. */
  readonly line: number;
}

type CacheDirective = "use cache" | "use cache: private";

/** Whether a function body opens with `directive`. */
function opensWith(body: Node | null, directive: CacheDirective): boolean {
  if (body?.type !== "BlockStatement") {
    return false;
  }

  const first = body.body[0];

  return first?.type === "ExpressionStatement" && first.directive === directive;
}

/**
 * The functions of `sources` whose first statement is `directive`: a
 * declaration, or a `const` or `let` that holds a function.
 */
function directiveFunctions(
  sources: readonly TextFile[],
  directive: CacheDirective,
): DirectiveFunction[] {
  const found: DirectiveFunction[] = [];

  for (const source of sources) {
    walk(parseSource(source.text).program, {
      enter(node, parent) {
        if (node.type === "FunctionDeclaration") {
          if (
            node.id !== null &&
            node.body !== null &&
            opensWith(node.body, directive)
          ) {
            found.push({
              name: node.id.name,
              file: source.path,
              body: node.body,
              line: lineColumn(source.text, node.start).line,
            });
          }

          return;
        }

        if (
          node.type === "VariableDeclarator" &&
          node.id.type === "Identifier" &&
          node.init !== null &&
          (node.init.type === "ArrowFunctionExpression" ||
            node.init.type === "FunctionExpression") &&
          node.init.body !== null &&
          opensWith(node.init.body, directive)
        ) {
          found.push({
            name: node.id.name,
            file: source.path,
            body: node.init.body,
            line: lineColumn(
              source.text,
              parent?.type === "VariableDeclaration"
                ? parent.start
                : node.start,
            ).line,
          });
        }
      },
    });
  }

  return found;
}

/**
 * A `"use cache: private"` function that calls another one (BS610): Next.js
 * doesn't allow private scopes inside each other, and each one resolves the
 * session again. Read in the outer function and pass the values down, or hand
 * every scope `bsb.sessionHandle()`.
 */
function nestedPrivateScopes(context: DoctorContext): FindingInput[] {
  const functions = directiveFunctions(context.sources, "use cache: private");
  const names = new Set(functions.map((fn) => fn.name));

  return functions.flatMap((outer) =>
    [...names]
      .filter(
        (name) =>
          name !== outer.name &&
          firstMatch(outer.body, (node) => isBareCall(node, name)) !==
            undefined,
      )
      .map((inner) => ({
        message: `${outer.file}: ${outer.name} runs in \`"use cache: private"\` and calls ${inner}, which has the same directive. Private cache scopes can't nest, and each one resolves the session again. Call ${inner} from the page and pass its result down, or read both in one scope.`,
        target: `${outer.file}:${outer.name}:${inner}`,
        location: { file: outer.file, line: outer.line },
      })),
  );
}

/**
 * A `"use cache: private"` function that uses the service role (BS611): the
 * private scope exists to keep per-user data, and an admin client reads past
 * the user's policies, so what it returns is cached under the user's key but
 * isn't theirs. Read as the user, or move the admin read out of the scope.
 */
function adminInPrivateScope(context: DoctorContext): FindingInput[] {
  return directiveFunctions(context.sources, "use cache: private").flatMap(
    (fn) =>
      firstMatch(
        fn.body,
        (node) =>
          isMemberCall(node, "bsb", "admin") ||
          isBareCall(node, "createAdminClient"),
      ) === undefined
        ? []
        : [
            {
              message: `${fn.file}: ${fn.name} runs in \`"use cache: private"\` and builds an admin client. The service role skips the user's policies, so its result doesn't belong in a per-user scope and each call costs an extra verification. Read as the user, or move the admin read out of the cached function.`,
              target: `${fn.file}:${fn.name}`,
              location: { file: fn.file, line: fn.line },
            },
          ],
  );
}

/**
 * A plain `"use cache"` function that reads the request (BS640): Next.js
 * rejects `cookies()` and `headers()` there, and `bsb.cached()` reads both. Use
 * `bsb.public()` for data every visitor may read, or a `: private` scope for
 * the user's own.
 */
function requestInPlainCache(context: DoctorContext): FindingInput[] {
  return directiveFunctions(context.sources, "use cache").flatMap((fn) =>
    firstMatch(
      fn.body,
      (node) =>
        isBareCall(node, "cookies", "headers") ||
        isMemberCall(node, "bsb", "cached", "context", "user"),
    ) === undefined
      ? []
      : [
          {
            message: `${fn.file}: ${fn.name} runs in \`"use cache"\` and reads the request (\`cookies()\`, \`headers()\`, \`bsb.cached()\`, \`bsb.context()\` or \`bsb.user()\`). Next.js rejects that in a shared scope. Call \`bsb.public()\` for data every visitor may read, or use \`"use cache: private"\` for the user's own.`,
            target: `${fn.file}:${fn.name}`,
            location: { file: fn.file, line: fn.line },
          },
        ],
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
  {
    code: "BS640",
    severity: "warning",
    title: "Request read inside a plain use cache scope",
    description:
      'A function with `"use cache"` calls `cookies()`, `headers()`, `bsb.cached()`, `bsb.context()` or `bsb.user()`. Next.js rejects request reads in a shared cache scope, and a per-user result must not be shared. Use `bsb.public()` for data every visitor may read, or `"use cache: private"` for the user\'s own.',
    check: requestInPlainCache,
  },
  {
    code: "BS646",
    severity: "warning",
    title: "Durable use cache entries with a shared reader",
    description:
      '`experimental.durableUseCacheEntries` keys a `"use cache"` entry on a hash of the code and the generated schema instead of the build, so `bsb.public()` and remote-scope entries outlive a deploy. A migration that changes a policy or a function body without changing the generated files, or a deployment on another Supabase project that shares the cache handler, then reads the old entries. Expire the tags after such a migration, keep one handler per Supabase project, or use `bsb.kept()` with a `version`.',
    check: durableSharedEntries,
  },
  ...CLIENT_BARREL_RULES,
  ...PUBLIC_KEPT_RULES,
  ...KEPT_EXPIRY_RULES,
  ...PROXY_SIZE_RULES,
];
