import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { parseCommandArgs } from "../../../src/cli/command.ts";
import {
  type CodemodArgs,
  codemodCommand,
  runCodemod,
} from "../../../src/cli/commands/codemod.ts";
import { resolveConfig } from "../../../src/config/index.ts";

describe("runCodemod", () => {
  let root: string;
  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bs-codemod-"));
    await mkdir(join(root, "src/lib"), { recursive: true });
    await mkdir(join(root, "node_modules/x"), { recursive: true });
    await writeFile(
      join(root, "src/lib/client.ts"),
      `import { createBrowser } from "better-supabase/react";\nexport const bs = createBrowser(betterSupabase);\nconst ctx = next.server();\n`,
    );
    await writeFile(join(root, "src/lib/other.ts"), "export const a = 1;\n");
    await writeFile(
      join(root, "src/types.d.ts"),
      "declare const createBrowser: 1;\n",
    );
    await writeFile(
      join(root, "node_modules/x/index.js"),
      `import { createBrowser } from "better-supabase/react";\n`,
    );
  });
  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const codemod = (argv: string[]) =>
    runCodemod(
      resolveConfig({}, root),
      // SAFETY: parseCommandArgs returns the declared args of codemodCommand.
      parseCommandArgs(codemodCommand, argv) as CodemodArgs,
    );

  it("asks for a known codemod", async () => {
    expect(await codemod([])).toMatchObject({
      code: 2,
      error: expect.stringContaining("Name a codemod:\n  0.4"),
    });
    expect(await codemod(["0.9"])).toMatchObject({
      code: 2,
      error: expect.stringContaining('Unknown codemod "0.9"'),
    });
  });

  it("shows the changes with --dry-run and writes them without", async () => {
    const path = join(root, "src/lib/client.ts");
    const before = await readFile(path, "utf8");
    const dry = await codemod(["0.4", "--dry-run"]);
    expect(dry.code).toBe(0);
    expect(dry.output).toContain(
      "Would update 1 of 2 files:\n  src/lib/client.ts",
    );
    expect(dry.output).toContain(
      "Check these by hand:\n  src/lib/client.ts:3: `next.server()` is `bs.context()`",
    );
    expect(await readFile(path, "utf8")).toBe(before);

    const done = await codemod(["0.4", "src"]);
    expect(done.output).toContain("Updated 1 of 2 files");
    expect(done.data).toMatchObject({
      codemod: "0.4",
      changed: ["src/lib/client.ts"],
    });
    expect(await readFile(path, "utf8")).toContain(
      "export const bs = createClient(betterSupabase);",
    );
    expect((await codemod(["0.4", "src/lib/client.ts"])).output).toContain(
      "Nothing to change in 1 files.",
    );
    expect((await codemod(["0.4", "missing"])).output).toBe(
      "Nothing to change in 0 files.",
    );
  });
});
