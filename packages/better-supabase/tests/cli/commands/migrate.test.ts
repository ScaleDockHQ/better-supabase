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
});
