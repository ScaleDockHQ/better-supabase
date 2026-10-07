import { execFile } from "node:child_process";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { promisify } from "node:util";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { importFresh } from "../../src/cli/fresh-import.ts";

const run = promisify(execFile);
const source = pathToFileURL(
  join(import.meta.dirname, "../../src/cli/fresh-import.ts"),
).href;

describe("importFresh", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-fresh-"));
    await mkdir(join(dir, "node_modules/dep"), { recursive: true });
    await writeFile(
      join(dir, "node_modules/dep/package.json"),
      JSON.stringify({ name: "dep", type: "module", exports: "./index.js" }),
    );
    await writeFile(
      join(dir, "node_modules/dep/index.js"),
      "export const loads = (globalThis.depLoads = (globalThis.depLoads ?? 0) + 1);\n",
    );
    await writeFile(
      join(dir, "entry.ts"),
      'import { value } from "./value.ts";\nimport { loads } from "dep";\nexport { value, loads };\n',
    );
    await writeFile(join(dir, "value.ts"), "export const value = 1;\n");
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("loads the entry's local imports again on every call, and packages once", async () => {
    const script = `
      import { writeFileSync } from "node:fs";
      import { importFresh } from ${JSON.stringify(source)};
      const entry = ${JSON.stringify(join(dir, "entry.ts"))};
      const first = await importFresh(entry);
      writeFileSync(${JSON.stringify(join(dir, "value.ts"))}, "export const value = 2;\\n");
      const second = await importFresh(entry);
      console.log(JSON.stringify([first.value, second.value, second.loads]));
    `;
    const { stdout } = await run(
      process.execPath,
      ["--input-type=module", "--no-warnings", "-e", script],
      { cwd: dir },
    );
    expect(JSON.parse(stdout)).toEqual([1, 2, 1]);
  });

  it("imports a module's exports", async () => {
    expect(await importFresh(join(dir, "value.ts"))).toMatchObject({
      value: 1,
    });
  });
});
