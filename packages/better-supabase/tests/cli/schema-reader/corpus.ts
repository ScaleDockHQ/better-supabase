import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const REPO = join(import.meta.dirname, "../../../../..");

/** Generated modules, the repo's own schema and a validation project. */
const CORPUS = [
  "packages/better-supabase/tests/sql/__golden__",
  "supabase/schemas",
  "tests/validation-centrakit/supabase/schemas",
];

export const SCHEMAS: readonly string[] = [
  "public",
  "better_supabase",
  "auth",
  "storage",
  "api",
  "_better_supabase",
  "rbac",
  "extensions",
  "workflow",
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
