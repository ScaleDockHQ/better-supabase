/**
 * Regenerates the Vue, Svelte and Solid entries of the blocks with a
 * controller (`src/blocks/<name>/{vue,svelte,solid}/index.ts`) from their
 * `client.ts`. `--check` lists stale files instead of writing them.
 */
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

import { renderBindings } from "../tests/blocks/bindings/render.ts";

const check = process.argv.includes("--check");
let stale = false;
for (const file of await renderBindings()) {
  if (check) {
    const current = await readFile(file.path, "utf-8").catch(() => "");
    if (current !== file.contents) {
      console.error(`stale: ${file.path}`);
      stale = true;
    }
  } else {
    await mkdir(dirname(file.path), { recursive: true });
    await writeFile(file.path, file.contents);
    console.log(`wrote ${file.path}`);
  }
}
process.exitCode = stale ? 1 : 0;
