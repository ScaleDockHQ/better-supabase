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

describe("codemod 0.15 in the app's SQL", () => {
  let root: string;

  const files: Record<string, string> = {
    "supabase/schemas/50_bsb_memberships.sql":
      "-- @bs-module memberships@3\ncreate function public.bs_member_role() returns text language sql as $$ select 'x' $$;\n",
    "supabase/schemas/10_app.sql":
      "create table public.docs (id uuid primary key);\ncreate trigger bs_broadcast_docs after insert on public.docs for each row execute function public.notify();\n",
    "supabase/tests/members.test.sql":
      "select is(public.bs_member_role(), 'x');\nselect bs_own_helper();\n",
    "supabase/tests/rls/roles.test.sql": "select bs_member_role();\n",
    "supabase/tests/README.md": "Run with supabase test db: bs_member_role\n",
    "supabase/tests/50_bsb_memberships.test.sql":
      "-- @bsb-block-test memberships\nselect public.bs_member_role();\n",
    "supabase/migrations/20240101000000_old.sql":
      "select public.bs_member_role();\n",
    "supabase/migrations/20240201000000_new.sql":
      "create view public.roles as\n  select public.bs_member_role() as role;\n",
    "supabase/migrations/20240301000000_better_supabase_modules.sql":
      "-- @bs-module memberships@3\nselect public.bs_member_role();\n",
  };

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-codemod-sql-"));

    for (const [path, text] of Object.entries(files)) {
      await mkdir(join(root, path, ".."), { recursive: true });
      await writeFile(join(root, path), text);
    }
  });
  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it("lists the renamed names in tests, app schemas and the newest migration, and writes no SQL", async () => {
    const result = await runCodemod(
      resolveConfig({}, root),
      parseCommandArgs(codemodCommand("0.15"), ["0.15"]),
    );

    expect(
      // SAFETY: runCodemod returns its review lines in `data.review`.
      (result.data as { review: { file: string; line: number }[] }).review.map(
        (hint) => `${hint.file}:${String(hint.line)}`,
      ),
    ).toEqual([
      "supabase/tests/members.test.sql:1",
      "supabase/tests/rls/roles.test.sql:1",
      "supabase/schemas/10_app.sql:2",
      "supabase/migrations/20240201000000_new.sql:2",
    ]);
    expect(result.output).toContain("Check these by hand:");
    expect(result.output).toContain(
      "supabase/tests/members.test.sql:1: bs_member_role is bsb_member_role since 0.15",
    );

    for (const [path, text] of Object.entries(files)) {
      expect(await readFile(join(root, path), "utf-8")).toBe(text);
    }
  });

  it("finds the names after upgrade rewrote the block files to bsb_", async () => {
    await writeFile(
      join(root, "supabase/schemas/50_bsb_memberships.sql"),
      "-- @bsb-block memberships@4 own\ncreate function public.bsb_member_role() returns text language sql as $$ select 'x' $$;\n",
    );
    await rm(
      join(
        root,
        "supabase/migrations/20240301000000_better_supabase_modules.sql",
      ),
    );

    const result = await runCodemod(
      resolveConfig({}, root),
      parseCommandArgs(codemodCommand("0.15"), ["0.15"]),
    );

    expect(result.output).toContain(
      "supabase/tests/members.test.sql:1: bs_member_role is bsb_member_role",
    );
    expect(result.output).not.toContain("bs_own_helper");
  });
});

describe("codemod 0.29", () => {
  let root: string;
  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-codemod-029-"));
  });
  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const run = (argv: string[] = []) =>
    runCodemod(
      resolveConfig({}, root),
      parseCommandArgs(codemodCommand("0.29"), ["0.29", ...argv]),
    );

  it("renames records to subjects, in the environment blocks too", async () => {
    const path = join(root, "better-supabase.config.ts");
    await writeFile(
      path,
      [
        `import { defineConfig } from "better-supabase/config";`,
        ``,
        `export default defineConfig({`,
        `  // Record types`,
        `  records: { task: { table: "tasks", title: "title" } },`,
        `  $env: { staging: { records: { note: { table: "notes" } } } },`,
        `  $production: { records: {} },`,
        `});`,
        ``,
      ].join("\n"),
    );

    await run();

    expect(await readFile(path, "utf-8")).toBe(
      [
        `import { defineConfig } from "better-supabase/config";`,
        ``,
        `export default defineConfig({`,
        `  // Record types`,
        `  subjects: { task: { table: "tasks", title: "title" } },`,
        `  $env: { staging: { subjects: { note: { table: "notes" } } } },`,
        `  $production: { subjects: {} },`,
        `});`,
        ``,
      ].join("\n"),
    );
  });

  it("moves records into an existing subjects, where subjects wins", async () => {
    const path = join(root, "better-supabase.config.ts");
    await writeFile(
      path,
      [
        `export default defineConfig({`,
        `  subjects: {`,
        `    task: { table: "tasks" },`,
        `  },`,
        `  records: {`,
        `    task: { table: "old_tasks" },`,
        `    note: { table: "notes" },`,
        `  },`,
        `  blocks: ["comments"],`,
        `});`,
        ``,
      ].join("\n"),
    );

    const result = await run();

    expect(await readFile(path, "utf-8")).toBe(
      [
        `export default defineConfig({`,
        `  subjects: {`,
        `    task: { table: "tasks" },`,
        `    note: { table: "notes" },`,
        `  },`,
        `  blocks: ["comments"],`,
        `});`,
        ``,
      ].join("\n"),
    );
    expect(result.output).toContain(
      "better-supabase.config.ts:6: `records.task` is dropped: `subjects.task` already exists and wins",
    );
  });

  it("renames records in a JSON config", async () => {
    const path = join(root, "better-supabase.config.json");
    await writeFile(
      path,
      `{ "records": { "task": { "table": "tasks" } }, "subjects": { "note": { "table": "notes" } } }\n`,
    );

    await run();

    expect(JSON.parse(await readFile(path, "utf-8"))).toEqual({
      subjects: { task: { table: "tasks" }, note: { table: "notes" } },
    });
  });

  it("renames record tags in schema files and leaves migrations alone", async () => {
    const schema = join(root, "supabase/schemas/public/tables/tasks.sql");
    const migration = join(root, "supabase/migrations/20260101000000_init.sql");
    await mkdir(join(root, "supabase/schemas/public/tables"), {
      recursive: true,
    });
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    const tagged = `create table public.tasks (id uuid primary key);\ncomment on table public.tasks is 'The team''s tasks @bsb record type=task title=title; realtime';\n`;
    await writeFile(schema, tagged);
    await writeFile(migration, tagged);

    const result = await run();

    expect(await readFile(schema, "utf-8")).toBe(
      `create table public.tasks (id uuid primary key);\ncomment on table public.tasks is 'The team''s tasks @bsb subject type=task title=title; realtime';\n`,
    );
    expect(await readFile(migration, "utf-8")).toBe(tagged);
    expect(result.data).toMatchObject({
      changed: ["supabase/schemas/public/tables/tasks.sql"],
    });
  });

  it("keeps a subject tag over a record tag", async () => {
    const schema = join(root, "supabase/schemas/public/tasks.sql");
    await mkdir(join(root, "supabase/schemas/public"), { recursive: true });
    await writeFile(
      schema,
      `comment on table tasks is '@bsb record type=old; subject type=task';\n`,
    );

    const result = await run();

    expect(await readFile(schema, "utf-8")).toBe(
      `comment on table tasks is '@bsb subject type=task';\n`,
    );
    expect(result.output).toContain(
      "supabase/schemas/public/tasks.sql:1: The `record` tag is dropped",
    );
  });
});
