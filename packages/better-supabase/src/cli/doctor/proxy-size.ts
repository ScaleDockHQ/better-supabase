import { existsSync } from "node:fs";
import { readFile, stat } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";

import type { Rule } from "./rules.ts";

/** The proxy's traced files, as `next build` listed them. */
export interface ProxyTrace {
  /** The trace file, relative to the project root. */
  readonly path: string;
  /** The files' sizes added up, in bytes. */
  readonly bytes: number;
  /** The five biggest files, by size. */
  readonly largest: readonly {
    readonly file: string;
    readonly bytes: number;
  }[];
}

/** Above this the proxy's start costs a visible part of every cold request. */
export const PROXY_BUDGET_BYTES = 400_000;

const TRACES = [
  ".next/server/proxy.js.nft.json",
  ".next/server/middleware.js.nft.json",
] as const;

/**
 * The proxy's file trace from the last `next build`, or `undefined` when the
 * project has not been built or has no proxy.
 */
export async function getProxyTrace(
  root: string,
): Promise<ProxyTrace | undefined> {
  const path = TRACES.find((trace) => existsSync(resolve(root, trace)));

  if (path === undefined) {
    return undefined;
  }

  const absolute = resolve(root, path);
  const parsed: unknown = JSON.parse(await readFile(absolute, "utf-8"));

  const listed: unknown =
    typeof parsed === "object" && parsed !== null
      ? Object.entries(parsed).find(([name]) => name === "files")?.[1]
      : undefined;

  if (!Array.isArray(listed)) {
    return undefined;
  }

  const names: readonly unknown[] = listed;

  const sizes = await Promise.all(
    names
      .filter((file): file is string => typeof file === "string")
      .map(async (file) => {
        const target = resolve(dirname(absolute), file);

        try {
          return {
            file: relative(root, target),
            bytes: (await stat(target)).size,
          };
        } catch {
          return { file: relative(root, target), bytes: 0 };
        }
      }),
  );

  return {
    path,
    bytes: sizes.reduce((sum, entry) => sum + entry.bytes, 0),
    largest: sizes.toSorted((a, b) => b.bytes - a.bytes).slice(0, 5),
  };
}

const kilobytes = (bytes: number): string => `${Math.round(bytes / 1000)} KB`;

/**
 * BS650: the proxy runs before every request, so what it imports decides every
 * request's start. Read from the trace of the last build.
 */
export const PROXY_SIZE_RULES: readonly Rule[] = [
  {
    code: "BS650",
    severity: "info",
    title: "The proxy bundle is large",
    description:
      "The last `next build` traced more than 400 KB of files for `proxy.ts`. It runs before every request, so the app definition, the generated schema or a block set in its imports slows each one. Build the proxy with `createProxy({ auth })` instead of passing the definition, and read permissions with the generated `proxy-permissions.generated.ts` catalog.",
    check: (context) => {
      const trace = context.proxyTrace;

      if (trace === undefined || trace.bytes <= PROXY_BUDGET_BYTES) {
        return [];
      }

      return [
        {
          message: `The proxy traces ${kilobytes(trace.bytes)} (budget ${kilobytes(PROXY_BUDGET_BYTES)}). Largest: ${trace.largest
            .map((entry) => `${entry.file} ${kilobytes(entry.bytes)}`)
            .join(", ")}.`,
          target: trace.path,
          location: { file: trace.path, line: 1 },
        },
      ];
    },
  },
];
