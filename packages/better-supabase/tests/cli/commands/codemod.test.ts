import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { CODEMODS } from "../../../src/cli/codemod.ts";
import {
  codemodCommand,
  runCodemod,
} from "../../../src/cli/commands/codemod.ts";
import { parseCommandArgs } from "../../../src/cli/core/command.ts";
import { findSpec } from "../../../src/cli/core/manifest.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { usageError } from "../fixtures/usage.ts";

describe("runCodemod", () => {
  let root: string;
  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-codemod-"));
    await mkdir(join(root, "src/lib"), { recursive: true });
    await mkdir(join(root, "node_modules/x"), { recursive: true });
    await writeFile(
      join(root, "src/lib/client.ts"),
      `import { createBrowser } from "better-supabase/react";\nexport const bsb = createBrowser(betterSupabase);\nconst ctx = next.server();\n`,
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
      // SAFETY: every codemod subcommand declares the same args, so any one parses `argv`.
      parseCommandArgs(codemodCommand("0.4"), argv),
    );

  it("has a subcommand for every registered codemod", () => {
    expect(
      findSpec(["codemod"])?.subcommands?.map((spec) => spec.name),
    ).toEqual(Object.keys(CODEMODS));
  });

  it("asks for a known codemod", async () => {
    expect(await usageError(() => codemod([]))).toContain(
      "Name a codemod:\n  0.4",
    );
    expect(await usageError(() => codemod(["0.99"]))).toContain(
      'Unknown codemod "0.99"',
    );
  });

  it("shows the changes with --dry-run and writes them without", async () => {
    const path = join(root, "src/lib/client.ts");
    const before = await readFile(path, "utf-8");
    const dry = await codemod(["0.4", "--dry-run"]);
    expect(dry.code).toBe(0);
    expect(dry.output).toContain(
      "Would update src/lib/client.ts\nWould update 1 of 2 files.",
    );
    expect(dry.output).toContain(
      "Check these by hand:\n  src/lib/client.ts:3: `next.server()` is `bsb.context()`",
    );
    expect(await readFile(path, "utf-8")).toBe(before);

    const done = await codemod(["0.4", "src"]);
    expect(done.output).toContain("Updated 1 of 2 files");
    expect(done.data).toMatchObject({
      codemod: "0.4",
      changed: ["src/lib/client.ts"],
    });
    expect(await readFile(path, "utf-8")).toContain(
      "export const bsb = createClient(betterSupabase);",
    );
    expect((await codemod(["0.4", "src/lib/client.ts"])).output).toContain(
      "Nothing to change in 1 files.",
    );
    expect((await codemod(["0.4", "missing"])).output).toBe(
      "Nothing to change in 0 files.",
    );
  });

  it("moves sql.modules in a JSON config with 0.9", async () => {
    const path = join(root, "better-supabase.config.json");
    await writeFile(path, `{ "sql": { "modules": ["tenant"] } }\n`);
    await writeFile(join(root, "other.json"), `{ "sql": { "modules": [] } }\n`);

    const done = await codemod(["0.9"]);
    expect(done.data).toMatchObject({
      changed: ["better-supabase.config.json"],
    });
    expect(JSON.parse(await readFile(path, "utf-8"))).toEqual({
      blocks: ["tenant"],
    });
  });
});
