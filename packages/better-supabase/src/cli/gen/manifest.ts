import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { isAbsolute, relative, resolve, sep } from "node:path";

import { CACHE_DIR, writeAtomic } from "../introspect/cache.ts";

/** The files the last `gen` wrote, so the next one can remove those it no longer writes. */
const MANIFEST = `${CACHE_DIR}/gen-manifest.json`;

export const manifestPath = (root: string, path: string): string =>
  relative(root, resolve(root, path)).split(sep).join("/");

async function readManifest(root: string): Promise<readonly string[]> {
  const parsed: unknown = await readFile(resolve(root, MANIFEST), "utf-8")
    .then((text): unknown => JSON.parse(text))
    .catch(() => undefined);
  if (
    typeof parsed !== "object" ||
    parsed === null ||
    !("version" in parsed) ||
    parsed.version !== 1 ||
    !("files" in parsed) ||
    !Array.isArray(parsed.files)
  ) {
    return [];
  }
  return parsed.files.filter(
    (path): path is string => typeof path === "string",
  );
}

/** Files in the last manifest that this run doesn't generate and that still exist inside the root. */
export async function leftoverFiles(
  root: string,
  generated: readonly string[],
): Promise<string[]> {
  const current = new Set(generated);
  return (await readManifest(root)).filter((path) => {
    const inside = relative(root, resolve(root, path));
    return (
      !current.has(path) &&
      inside !== "" &&
      !inside.startsWith("..") &&
      !isAbsolute(inside) &&
      existsSync(resolve(root, path))
    );
  });
}

export const writeManifest = (
  root: string,
  files: readonly string[],
): Promise<void> =>
  writeAtomic(
    resolve(root, MANIFEST),
    `${JSON.stringify({ version: 1, files: [...files].sort() }, null, 2)}\n`,
  ).catch(() => undefined);
