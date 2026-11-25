import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  configImportsHash,
  configImportsKey,
  rememberConfigImports,
} from "../../../src/cli/cache/config-imports.ts";
import { getConfig } from "../../../src/cli/config.ts";

let root = "";

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "bsb-config-imports-"));
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

const write = async (name: string, text: string): Promise<string> => {
  const path = join(root, name);
  await mkdir(join(path, ".."), { recursive: true });
  await writeFile(path, text);

  return path;
};

describe("configImportsHash", () => {
  it("changes when the config file changes", async () => {
    const config = await write("config.ts", "export default {};");
    const before = await configImportsHash(config);

    await write("config.ts", "export default { a: 1 };");

    expect(await configImportsHash(config)).not.toBe(before);
  });

  it("changes when a file imported through another one changes", async () => {
    const config = await write(
      "config.ts",
      'import { rows } from "./lib/rows.ts";\nexport default rows;',
    );

    await write("lib/rows.ts", 'export { rows } from "./deep.js";');
    await write("lib/deep.ts", "export const rows = 1;");
    const before = await configImportsHash(config);

    await write("lib/deep.ts", "export const rows = 2;");

    expect(await configImportsHash(config)).not.toBe(before);
  });

  it("follows a dynamic import and a directory index", async () => {
    const config = await write(
      "config.ts",
      'export default await import("./parts");',
    );

    await write("parts/index.ts", "export default 1;");
    const before = await configImportsHash(config);

    await write("parts/index.ts", "export default 2;");

    expect(await configImportsHash(config)).not.toBe(before);
  });

  it("ignores packages, missing files and import cycles", async () => {
    const config = await write(
      "config.ts",
      'import "better-supabase";\nimport "./gone.ts";\nimport "./a.ts";',
    );

    await write("a.ts", 'import "./config.ts";');

    expect(await configImportsHash(config)).toBe(
      await configImportsHash(config),
    );
  });
});

describe("configImportsKey", () => {
  it("returns what getConfig recorded for a root, and an empty key otherwise", () => {
    expect(configImportsKey(join(root, "none"))).toBe("");

    rememberConfigImports(root, "abc");

    expect(configImportsKey(root)).toBe("abc");
  });
});

describe("getConfig", () => {
  it("records the imports hash of the config it loaded", async () => {
    await write("lib/helper.ts", "export const schema = 'one';");

    const config = await write(
      "better-supabase.config.ts",
      'import { schema } from "./lib/helper.ts";\nexport default { database: { sql: { schema } } };',
    );

    await getConfig(root, undefined, undefined, config);
    const first = configImportsKey(root);

    expect(first).toBe(await configImportsHash(config));

    await write("lib/helper.ts", "export const schema = 'two';");
    await getConfig(root, undefined, undefined, config);

    expect(configImportsKey(root)).not.toBe(first);
  });
});
