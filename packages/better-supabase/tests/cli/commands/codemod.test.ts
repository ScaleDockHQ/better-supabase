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
import { CliError } from "../../../src/cli/core/errors.ts";
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

  it("never rewrites a block file, even when a path names it", async () => {
    const block = join(root, "supabase/schemas/900_better_supabase_x.sql");
    const text = `-- @bsb-block x 1\nimport { buildJsonSchema } from "better-supabase/config";\n`;

    await mkdir(join(root, "supabase/schemas"), { recursive: true });
    await writeFile(block, text);

    const result = await codemod(["naming", "supabase/schemas"]);

    const direct = await runCodemod(
      resolveConfig({}, root),
      // SAFETY: every codemod subcommand declares the same args, so any one parses `argv`.
      parseCommandArgs(codemodCommand("naming"), [
        "naming",
        "supabase/schemas/900_better_supabase_x.sql",
      ]),
    );

    expect(result.code).toBe(0);
    expect(direct.code).toBe(0);
    expect(await readFile(block, "utf-8")).toBe(text);
    expect(direct.output).toContain("A block file");
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
      migration: () => ({ sql: "select 1;\n" }),
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
    expect(names[0]).toMatch(
      /^\d{14}_better_supabase_with-sql_[0-9a-f]{8}\.sql$/u,
    );
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

  it("moves the policy helper functions the project's SQL names", async () => {
    await mkdir(join(root, "supabase/schemas"), { recursive: true });
    await writeFile(
      join(root, "supabase/schemas/notes.sql"),
      "create policy p on notes using (bsb.owns(owner_id));\n",
    );

    await codemod(["naming"]);

    const [name] = await readdir(join(root, "supabase/migrations"));

    const sql = await readFile(
      join(root, "supabase/migrations", name!),
      "utf-8",
    );

    expect(sql).toContain("alter function bsb.owns(uuid) set schema");
    expect(sql).not.toContain("bsb.uid()");
  });

  it("leaves the files the blocks wrote out of the names it moves", async () => {
    await mkdir(join(root, "supabase/schemas"), { recursive: true });
    await writeFile(
      join(root, "supabase/schemas/900_better_supabase_001_notes.sql"),
      "-- better-supabase module: notes\n-- @bsb-block notes@1 managed\n\ncreate policy p on notes using (bsb.owns(owner_id));\n",
    );

    await codemod(["naming"]);

    expect(await readdir(join(root, "supabase"))).not.toContain("migrations");
  });

  it("writes no SQL migration while the table has no SQL renames", async () => {
    await codemod(["naming"]);
    expect(await readdir(root)).not.toContain("supabase");
  });
});

describe("codemod extra-columns", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-extra-columns-"));
    await mkdir(join(root, "supabase/schemas"), { recursive: true });
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it("moves the columns into <table>.ext.sql and out of the config", async () => {
    const configPath = join(root, "better-supabase.config.ts");

    await writeFile(
      configPath,
      `export default {\n  blocks: {\n    tags: {\n      options: {\n        extraColumns: { region: "text not null default 'eu'" },\n      },\n    },\n  },\n};\n`,
    );

    const config = resolveConfig(
      {
        blocks: {
          memberships: {},
          tags: {
            // SAFETY: the option was removed from the types; the codemod reads
            // the old config form.
            options: {
              extraColumns: { region: "text not null default 'eu'" },
            } as never,
          },
        },
      },
      root,
    );

    const done = await runCodemod(
      config,
      // SAFETY: every codemod subcommand declares the same args.
      parseCommandArgs(codemodCommand("extra-columns"), ["extra-columns"]),
      undefined,
      configPath,
    );

    expect(done.code).toBe(0);

    const ext = await readFile(
      join(root, "supabase/schemas/tags.ext.sql"),
      "utf-8",
    );

    expect(ext).toContain("add column \"region\" text not null default 'eu'");
    expect(await readFile(configPath, "utf-8")).not.toContain("extraColumns");
  });

  it("changes nothing for a config without the options", async () => {
    const done = await runCodemod(
      resolveConfig({ blocks: ["memberships", "tags"] }, root),
      // SAFETY: every codemod subcommand declares the same args.
      parseCommandArgs(codemodCommand("extra-columns"), ["extra-columns"]),
    );

    expect(done.output).toContain("Nothing to change");
  });

  it("keeps the configured tenant column out of the rename migration", async () => {
    await mkdir(join(root, "supabase/schemas"), { recursive: true });
    await writeFile(
      join(root, "supabase/schemas/010_app.sql"),
      "create table app.notes (organization_id uuid, locked_until timestamptz);\n",
    );

    await runCodemod(
      resolveConfig(
        { database: { sql: { tenantColumn: "organization_id" } } },
        root,
      ),
      parseCommandArgs(codemodCommand("naming"), ["naming"]),
    );

    const names = await readdir(join(root, "supabase/migrations")).catch(
      () => [],
    );

    const sql = await Promise.all(
      names.map((name) =>
        readFile(join(root, "supabase/migrations", name), "utf-8"),
      ),
    );

    expect(sql.join("\n")).not.toContain('rename column "organization_id"');
    expect(sql.join("\n")).toContain('rename column "locked_until"');
  });

  it("leaves the column renames out and says so when the config did not load", async () => {
    await mkdir(join(root, "supabase/schemas"), { recursive: true });
    await writeFile(
      join(root, "supabase/schemas/010_app.sql"),
      "create table app.notes (organization_id uuid);\n",
    );

    const result = await runCodemod(
      resolveConfig({}, root),
      parseCommandArgs(codemodCommand("naming"), ["naming"]),
      undefined,
      undefined,
      new CliError("config_invalid", "bad config"),
    );

    expect(result.output).toContain("The config did not load");

    const names = await readdir(join(root, "supabase/migrations")).catch(
      () => [],
    );

    for (const name of names) {
      expect(
        await readFile(join(root, "supabase/migrations", name), "utf-8"),
      ).not.toContain("rename column");
    }
  });

  it("fails a project codemod with config_invalid when the config did not load", async () => {
    await expect(
      runCodemod(
        resolveConfig({}, root),
        parseCommandArgs(codemodCommand("owned-columns"), ["owned-columns"]),
        undefined,
        undefined,
        new CliError("config_invalid", "bad config"),
      ),
    ).rejects.toMatchObject({ code: "config_invalid" });
  });

  it("renames block columns in schema files and seeds, never in migrations", async () => {
    await mkdir(join(root, "supabase/schemas"), { recursive: true });
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    const seed = "update better_supabase.drive_nodes set deleted_at = now();\n";
    await writeFile(join(root, "supabase/seed.sql"), seed);
    await writeFile(
      join(root, "supabase/migrations/20260101000000_old.sql"),
      seed,
    );
    await writeFile(
      join(root, "supabase/schemas/010_app.sql"),
      "update public.documents set deleted_at = now();\n",
    );

    await runCodemod(
      resolveConfig({}, root),
      parseCommandArgs(codemodCommand("naming"), ["naming"]),
    );

    expect(await readFile(join(root, "supabase/seed.sql"), "utf-8")).toBe(
      "update better_supabase.drive_nodes set archived_at = now();\n",
    );
    expect(
      await readFile(
        join(root, "supabase/migrations/20260101000000_old.sql"),
        "utf-8",
      ),
    ).toBe(seed);
    expect(
      await readFile(join(root, "supabase/schemas/010_app.sql"), "utf-8"),
    ).toContain("public.documents set deleted_at");

    const failed = await runCodemod(
      resolveConfig({}, root),
      parseCommandArgs(codemodCommand("naming"), ["naming"]),
      undefined,
      undefined,
      new CliError("config_invalid", "bad config"),
    );

    expect(failed.output).toContain("The config did not load");
  });

  it("pins the old name of a column the app's own block table keeps", async () => {
    await mkdir(join(root, "supabase/schemas"), { recursive: true });
    await writeFile(
      join(root, "supabase/schemas/010_app.sql"),
      "create table public.drive_nodes (id uuid primary key, tenant_id uuid, name text, deleted_at timestamptz);\n",
    );
    const configFile = join(root, "bsb.config.ts");

    await writeFile(
      configFile,
      'export default { blocks: { drive: { tables: { nodes: "public.drive_nodes" } } } };\n',
    );

    const config = resolveConfig(
      { blocks: { drive: { tables: { nodes: "public.drive_nodes" } } } },
      root,
    );

    await runCodemod(
      config,
      parseCommandArgs(codemodCommand("naming"), ["naming"]),
      undefined,
      configFile,
    );

    expect(await readFile(configFile, "utf-8")).toContain(
      'columns: { nodes: { deletedAt: "deleted_at" } }',
    );

    // Pinned, so a second run changes nothing.
    const second = await runCodemod(
      resolveConfig(
        {
          blocks: {
            drive: {
              tables: { nodes: "public.drive_nodes" },
              columns: { nodes: { deletedAt: "deleted_at" } },
            },
          },
        },
        root,
      ),
      parseCommandArgs(codemodCommand("naming"), ["naming"]),
      undefined,
      configFile,
    );

    expect(second.output).not.toContain("bsb.config.ts");
    expect(
      (await readFile(configFile, "utf-8")).match(/deletedAt/g),
    ).toHaveLength(1);
  });

  it("lists a pin it can't write into the config", async () => {
    await mkdir(join(root, "supabase/schemas"), { recursive: true });
    await writeFile(
      join(root, "supabase/schemas/010_app.sql"),
      "create table public.drive_nodes (id uuid primary key, tenant_id uuid, name text, deleted_at timestamptz);\n",
    );
    const configFile = join(root, "bsb.config.ts");

    await writeFile(configFile, "export default defineConfig(base);\n");

    const result = await runCodemod(
      resolveConfig(
        { blocks: { drive: { tables: { nodes: "public.drive_nodes" } } } },
        root,
      ),
      parseCommandArgs(codemodCommand("naming"), ["naming"]),
      undefined,
      configFile,
    );

    expect(result.output).toContain('deletedAt: "deleted_at"');
  });
});
