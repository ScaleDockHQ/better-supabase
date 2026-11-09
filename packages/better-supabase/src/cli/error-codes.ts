import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

import { ERROR_CODES } from "./error-codes.data.ts";

/** One stable code a module raises or an import warning reports. */
export interface ErrorCodeEntry {
  readonly code: string;
  readonly message?: string;
}

export { ERROR_CODES };

/** A code from the catalog. */
export type ErrorCode = (typeof ERROR_CODES)[number]["code"];

const PATTERNS = [
  /fail\(\s*["']([A-Z][A-Z0-9_]+)["']\s*,\s*["']([^"']*)["']/gu,
  /hint = '([A-Z][A-Z0-9_]+)'/gu,
  /'code',\s*'([A-Z][A-Z0-9_]+)'(?:\s*,\s*'message',\s*'([^']*)')?/gu,
];

/** Codes a SQL module tree raises, in code order. */
export async function scanErrorCodes(
  root: string,
): Promise<readonly ErrorCodeEntry[]> {
  const found = new Map<string, string | undefined>();

  const walk = async (dir: string): Promise<void> => {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);

      if (entry.isDirectory()) {
        await walk(path);
      } else if (entry.name.endsWith(".ts")) {
        const text = await readFile(path, "utf-8");

        for (const pattern of PATTERNS) {
          for (const match of text.matchAll(
            new RegExp(pattern.source, pattern.flags),
          )) {
            const code = match[1];
            const message = match[2];

            if (code === undefined) {
              continue;
            }

            if (!found.has(code)) {
              found.set(code, message);
            } else if (found.get(code) === undefined && message !== undefined) {
              found.set(code, message);
            }
          }
        }
      }
    }
  };

  await walk(root);

  return [...found.entries()]
    .toSorted(([left], [right]) => left.localeCompare(right))
    .map(([code, message]) =>
      message === undefined ? { code } : { code, message },
    );
}
