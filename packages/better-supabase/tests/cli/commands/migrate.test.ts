import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { run } from "../../../src/cli/core/run.ts";

describe("migrate schema-first", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-migrate-"));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("has nothing to move without appTables", async () => {
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({ blocks: [] }),
    );

    const result = await run(["migrate", "schema-first", "--cwd", dir]);

    expect(result).toMatchObject({ code: 0 });
    expect(result.stdout).toContain("no tables to move");
  });

  it("writes one file per app table with its tags", async () => {
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        blocks: [],
        tables: {
          invoices: {
            owner: "none",
            columns: { number: { type: "text" } },
            subject: { type: "invoice", title: "number" },
          },
        },
        database: { realtime: { tables: ["invoices"] } },
      }),
    );

    const result = await run(["migrate", "schema-first", "--cwd", dir]);

    expect(result).toMatchObject({ code: 0 });

    const text = await readFile(
      join(dir, "supabase/schemas/public/tables/invoices.sql"),
      "utf-8",
    );

    expect(text).not.toContain("@bsb-hash");
    expect(text).toContain("create table");
    expect(text).toMatch(
      /comment on table public\.invoices is '@bsb [^']*subject/u,
    );
    expect(text).toContain("realtime");
  });

  it("types a format column as a domain in the bsb schema", async () => {
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        blocks: [],
        tables: {
          people: {
            owner: "none",
            columns: {
              email: { type: "text", format: "email" },
              stars: { type: "integer", format: "rating" },
              score: { type: "integer", format: "rating", max: 3 },
              phone: { type: "text", format: "phone" },
            },
          },
        },
      }),
    );

    const result = await run(["migrate", "schema-first", "--cwd", dir]);

    expect(result).toMatchObject({ code: 0 });

    const schemas = join(dir, "supabase/schemas");

    const table = await readFile(
      join(schemas, "public/tables/people.sql"),
      "utf-8",
    );

    expect(table).toMatch(/"?email"? bsb\.email/u);
    expect(table).toMatch(/"?stars"? bsb\.rating/u);
    expect(table).toMatch(/"?score"? integer/u);
    expect(table).toMatch(/"?phone"? text/u);
    expect(table).not.toContain("people_email_check");
    expect(table).toContain("people_score_check");

    expect(await readFile(join(schemas, "bsb/schema.sql"), "utf-8")).toContain(
      "create schema if not exists bsb;",
    );

    const email = await readFile(
      join(schemas, "bsb/domains/email.sql"),
      "utf-8",
    );

    expect(email).toContain("create domain bsb.email as text");
    expect(email).toContain("constraint email_check check (value ~*");

    expect(
      await readFile(join(schemas, "bsb/domains/rating.sql"), "utf-8"),
    ).toContain("value >= 1 and value <= 5");

    await expect(
      readFile(join(schemas, "bsb/domains/phone.sql"), "utf-8"),
    ).rejects.toThrow(/ENOENT/u);
  });

  it("writes a rollup as a security invoker view in its own file", async () => {
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        blocks: [],
        tables: {
          projects: {
            owner: "none",
            columns: { name: { type: "text" } },
            rollups: {
              task_count: {
                table: "tasks",
                via: "project_id",
                aggregate: "count",
              },
            },
          },
          tasks: {
            owner: "none",
            columns: {
              project_id: {
                type: "uuid",
                nullable: false,
                references: { table: "projects", onDelete: "cascade" },
              },
            },
          },
        },
      }),
    );

    const result = await run(["migrate", "schema-first", "--cwd", dir]);

    expect(result).toMatchObject({ code: 0 });

    const view = await readFile(
      join(dir, "supabase/schemas/public/views/projects_view.sql"),
      "utf-8",
    );

    expect(view).toContain("with (security_invoker = true)");
    expect(view).not.toContain("drop view");
  });

  it("writes above the project root when supabase lives in the monorepo root", async () => {
    const app = join(dir, "apps", "web");

    await mkdir(app, { recursive: true });
    await mkdir(join(dir, "supabase"), { recursive: true });
    await writeFile(join(dir, "supabase", "config.toml"), 'project_id = "x"\n');

    await writeFile(
      join(app, "better-supabase.config.json"),
      JSON.stringify({
        blocks: [],
        tables: {
          notes: { owner: "none", columns: { body: { type: "text" } } },
        },
      }),
    );

    const result = await run(["migrate", "schema-first", "--cwd", app]);

    expect(result).toMatchObject({ code: 0 });

    const text = await readFile(
      join(dir, "supabase/schemas/public/tables/notes.sql"),
      "utf-8",
    );

    expect(text).toContain("create table");
  });

  it("reads the removed records key, and other commands refuse it", async () => {
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        blocks: [],
        records: { invoice: { table: "invoices" } },
        tables: {
          invoices: { owner: "none", columns: { number: { type: "text" } } },
        },
      }),
    );

    const migrated = await run([
      "migrate",
      "schema-first",
      "--dry-run",
      "--cwd",
      dir,
    ]);

    expect(migrated).toMatchObject({ code: 0 });

    const refused = await run(["doctor", "--cwd", dir]);

    expect(refused.code).not.toBe(0);
    expect(refused.stderr).toContain("migrate schema-first");
    expect(refused.stderr).toContain("renamed to `subjects`");
  });
});
