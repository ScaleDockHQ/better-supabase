/**
 * Regenerates the runtime test fixtures from `supabase/snapshot.json`. The
 * snapshot itself comes from a freshly reset fixture database: `pnpm
 * supabase:reset`, then `node packages/better-supabase/src/cli/bin.ts
 * introspect --cwd .`
 */
import { readFile, writeFile } from "node:fs/promises";

import { renderFixtures } from "../tests/cli/fixtures/render.ts";

const check = process.argv.includes("--check");
let stale = false;

for (const file of await renderFixtures()) {
  if (check) {
    const current = await readFile(file.path, "utf-8").catch(() => "");

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
