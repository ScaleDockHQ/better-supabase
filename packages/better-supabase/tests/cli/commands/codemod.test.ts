import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { Codemod } from "../../../src/cli/codemod.ts";

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
      `import { buildJsonSchema } from "better-supabase/config";\nexport const schema = buildJsonSchema({});\nconst stack = process.env.BSB_STACK;\n`,
    );
    await writeFile(join(root, "src/lib/other.ts"), "export const a = 1;\n");
    await writeFile(join(root, ".env.example"), "BSB_CLOUD_URL=\nOTHER=1\n");
    await writeFile(
      join(root, "src/types.d.ts"),
      "declare const buildJsonSchema: 1;\n",
    );
    await writeFile(
      join(root, "node_modules/x/index.js"),
      `import { buildJsonSchema } from "better-supabase/config";\n`,
    );
  });
  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const codemod = (argv: string[]) =>
    runCodemod(
      resolveConfig({}, root),
      // SAFETY: every codemod subcommand declares the same args, so any one parses `argv`.
      parseCommandArgs(codemodCommand("naming"), argv),
    );

  it("has a subcommand for every registered codemod", () => {
    expect(
      findSpec(["codemod"])?.subcommands?.map((spec) => spec.name),
    ).toEqual(Object.keys(CODEMODS));
  });

  it("asks for a known codemod", async () => {
    expect(await usageError(() => codemod([]))).toContain(
      "Name a codemod:\n  naming",
    );
    expect(await usageError(() => codemod(["0.99"]))).toContain(
      'Unknown codemod "0.99"',
    );
  });

  it("shows the changes with --dry-run and writes them without", async () => {
    const path = join(root, "src/lib/client.ts");
    const before = await readFile(path, "utf-8");
    const dry = await codemod(["naming", "--dry-run"]);
    expect(dry.code).toBe(0);
    expect(dry.output).toContain("Would update src/lib/client.ts");
    expect(dry.output).toContain("Would update .env.example");
    expect(dry.output).toContain("Would update 2 of 3 files.");
    expect(await readFile(path, "utf-8")).toBe(before);

    const done = await codemod(["naming", "src", ".env.example"]);
    expect(done.output).toContain("Updated 2 of 3 files");
    expect(done.data).toMatchObject({ codemod: "naming" });
    expect(await readFile(path, "utf-8")).toBe(
      `import { toJsonSchema } from "better-supabase/config";\nexport const schema = toJsonSchema({});\nconst stack = process.env.BETTER_SUPABASE_STACK;\n`,
    );
    expect(await readFile(join(root, ".env.example"), "utf-8")).toBe(
      "BETTER_SUPABASE_CLOUD_URL=\nOTHER=1\n",
    );
    expect((await codemod(["naming", "src/lib/client.ts"])).output).toContain(
      "Nothing to change in 1 files.",
    );
    expect((await codemod(["naming", "missing"])).output).toBe(
      "Nothing to change in 0 files.",
    );
  });

  it("writes the SQL a codemod returns as one new migration", async () => {
    // SAFETY: CODEMODS is a plain object; the test adds one entry and removes it.
    const registry = CODEMODS as Record<string, Codemod>;

    registry["with-sql"] = {
      name: "with-sql",
      description: "test",
      migration: () => "select 1;\n",
    };

    try {
      await runCodemod(
        resolveConfig({}, root),
        parseCommandArgs(codemodCommand("naming"), ["with-sql"]),
      );
    } finally {
      delete registry["with-sql"];
    }

    const names = await readdir(join(root, "supabase/migrations"));

    expect(names).toHaveLength(1);
    expect(names[0]).toMatch(/^\d{14}_better_supabase_with-sql\.sql$/u);
    expect(
      await readFile(join(root, "supabase/migrations", names[0]!), "utf-8"),
    ).toBe("select 1;\n");
  });

  it("lists the lines a codemod leaves for review", async () => {
    await writeFile(
      join(root, "src/lib/reads.ts"),
      "await Promise.all([db.customers.list(), db.orders.count()]);\n",
    );

    const result = await codemod(["read-many", "src/lib/reads.ts"]);

    expect(result.output).toContain("Check these by hand:");
    expect(result.output).toContain("src/lib/reads.ts:1:");
  });

  it("writes no SQL migration while the table has no SQL renames", async () => {
    await codemod(["naming"]);
    expect(await readdir(root)).not.toContain("supabase");
  });
});
