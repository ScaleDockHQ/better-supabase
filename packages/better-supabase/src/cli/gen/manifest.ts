import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { isAbsolute, posix, relative, resolve, sep } from "node:path";

import { CACHE_DIR, writeAtomic } from "../introspect/cache.ts";
import { GENERATED_HEADER } from "./emit.ts";

/**
 * The files the last `gen` wrote, so the next one can remove those it no longer
 * writes.
 */
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

const insideRoot = (root: string, path: string): boolean => {
  const inside = relative(root, resolve(root, path));

  return inside !== "" && !inside.startsWith("..") && !isAbsolute(inside);
};

/**
 * The TypeScript files next to this run's own that carry gen's header but that
 * this run doesn't generate. Unlike the manifest, which only the machine that
 * ran `gen` last has, this reads the tree, so `gen --check` reports the same
 * leftovers in CI as locally.
 */
async function headedLeftovers(
  root: string,
  current: ReadonlySet<string>,
): Promise<readonly string[]> {
  const folders = new Set(
    [...current]
      .filter((path) => path.endsWith(".ts") && insideRoot(root, path))
      .map((path) => posix.dirname(path)),
  );

  const found = await Promise.all(
    [...folders].map(async (folder) => {
      const names = await readdir(resolve(root, folder)).catch(() => []);

      const headed = await Promise.all(
        names
          .filter((name) => name.endsWith(".ts"))
          .map((name) => posix.join(folder, name))
          .filter((path) => !current.has(path))
          .map(async (path) => {
            const text = await readFile(resolve(root, path), "utf-8").catch(
              () => "",
            );

            return text.startsWith(GENERATED_HEADER) ? [path] : [];
          }),
      );

      return headed.flat();
    }),
  );

  return found.flat();
}

/**
 * Files this run doesn't generate that still exist inside the root: those in
 * the last manifest, and those in the folders gen writes that carry its
 * header.
 */
export async function leftoverFiles(
  root: string,
  generated: readonly string[],
): Promise<string[]> {
  const current = new Set(generated);

  const listed = (await readManifest(root)).filter(
    (path) =>
      !current.has(path) &&
      insideRoot(root, path) &&
      existsSync(resolve(root, path)),
  );

  return [
    ...new Set([...listed, ...(await headedLeftovers(root, current))]),
  ].toSorted();
}

export const writeManifest = (
  root: string,
  files: readonly string[],
): Promise<void> =>
  writeAtomic(
    resolve(root, MANIFEST),
    `${JSON.stringify({ version: 1, files: files.toSorted() }, null, 2)}\n`,
  ).catch(() => undefined);
