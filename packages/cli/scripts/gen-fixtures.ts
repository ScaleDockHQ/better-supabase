/**
 * Regenerates the runtime test fixtures from `tests/fixtures/snapshot.json`.
 * The snapshot itself comes from the repo's fixture database:
 * `node packages/cli/src/bin.ts introspect --cwd . --out packages/better-supabase/tests/fixtures/snapshot.json`
 */
import { readFile, writeFile } from "node:fs/promises";

import { renderFixtures } from "../tests/fixtures/render.ts";

const check = process.argv.includes("--check");
let stale = false;
for (const file of await renderFixtures()) {
  if (check) {
    const current = await readFile(file.path, "utf8").catch(() => "");
    if (current !== file.contents) {
      console.error(`stale: ${file.path}`);
      stale = true;
    }
  } else {
    await writeFile(file.path, file.contents);
    console.log(`wrote ${file.path}`);
  }
}
process.exitCode = stale ? 1 : 0;
