import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const REPO = join(import.meta.dirname, "../../../../..");

/** Generated modules, the repo's own schema and a validation project. */
const CORPUS = [
  "packages/better-supabase/tests/sql/__golden__",
  "supabase/schemas",
  "tests/validation-centrakit/supabase/schemas",
];

function walk(directory: string, found: string[] = []): string[] {
  for (const entry of readdirSync(directory)) {
    const path = join(directory, entry);

    if (statSync(path).isDirectory()) {
      walk(path, found);
    } else if (path.endsWith(".sql")) {
      found.push(path);
    }
  }

  return found;
}

export interface CorpusFile {
  readonly path: string;
  readonly name: string;
  readonly text: string;
}

export const files: readonly CorpusFile[] = CORPUS.flatMap((directory) =>
  walk(join(REPO, directory)),
).map((path) => ({
  path,
  name: relative(REPO, path),
  text: readFileSync(path, "utf-8"),
}));

const REGRESS = join(import.meta.dirname, "fixtures/pg-regress");

/** Postgres regression scripts (`SOURCES.md`), cut to what parses. */
export const regressFiles: readonly CorpusFile[] = readdirSync(REGRESS)
  .filter((entry) => entry.endsWith(".sql"))
  .map((entry) => join(REGRESS, entry))
  .map((path) => ({
    path,
    name: relative(REGRESS, path),
    text: readFileSync(path, "utf-8"),
  }));

const POSITIONS = new Set(["location", "stmt_location", "stmt_len"]);

/** A parse tree without the fields that only say where a node was written. */
export function cleanTree(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(cleanTree);
  }

  if (typeof value !== "object" || value === null) {
    return value;
  }

  return Object.fromEntries(
    Object.entries(value)
      .filter(([key]) => !POSITIONS.has(key))
      .map(([key, child]) => [key, cleanTree(child)]),
  );
}
