import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

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

export const NEXT_CACHE_RULES: readonly Rule[] = [
  {
    code: "BS608",
    severity: "warning",
    title: "Remote cache scope without a remote cache handler",
    description:
      "`bsb.remote()` and `bsb.cached({ scope: \"remote\" })` run in `'use cache: remote'`. Vercel provides a shared remote handler; elsewhere Next.js falls back to an in-memory one per instance, so entries are never shared and every deploy starts cold. Set `cacheHandlers.remote` (`remoteCacheHandler` in `createNextConfig`).",
    check: remoteWithoutHandler,
  },
];
