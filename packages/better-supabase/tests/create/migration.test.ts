import { describe, expect, it } from "vitest";

import type { CreateDesign } from "../../src/preset/index.ts";

import { migrationBetween, previewFiles } from "../../src/create/index.ts";
import { validateDesign } from "../../src/create/lite/index.ts";
import { presetSpec, namedPreset } from "../../src/preset/index.ts";

const code = presetSpec(namedPreset("saas"));

const notes: CreateDesign = {
  appTables: {
    notes: { columns: { title: { type: "text", nullable: false } } },
  },
};

describe("migrationBetween", () => {
  it("writes nothing when nothing changed", () => {
    expect(migrationBetween(code, notes, notes)).toEqual({
      ok: true,
      sql: "",
      changes: [],
    });
  });

  it("adds a table and a column", () => {
    const plan = migrationBetween(code, notes, {
      appTables: {
        notes: {
          columns: {
            title: { type: "text", nullable: false },
            body: { type: "text" },
          },
        },
        tags: { columns: { name: { type: "text", nullable: false } } },
      },
    });

    expect(plan.ok).toBe(true);
    expect(plan.changes.map((change) => change.kind)).toEqual([
      "column.added",
      "table.added",
    ]);

    expect(plan).toMatchObject({
      sql: expect.stringContaining('add column if not exists "body" text'),
    });
    expect(plan).toMatchObject({
      sql: expect.stringContaining(
        'create table if not exists "public"."tags"',
      ),
    });
  });

  it("refuses a dropped column as breaking", () => {
    const plan = migrationBetween(code, notes, {
      appTables: { notes: { columns: {} } },
    });

    expect(plan).toMatchObject({ ok: false, reason: "breaking" });
  });

  it("refuses a changed default as unsupported", () => {
    const plan = migrationBetween(code, notes, {
      appTables: {
        notes: {
          columns: { title: { type: "text", nullable: false, default: "'x'" } },
        },
      },
    });

    expect(plan).toMatchObject({ ok: false, reason: "unsupported" });
  });

  it("refuses a change outside the app tables", () => {
    const projects = presetSpec(namedPreset("projects"));

    const plan = migrationBetween(projects, notes, {
      ...notes,
      extraColumns: { tags: { weight: "integer not null default 0" } },
    });

    expect(plan).toMatchObject({ ok: false, reason: "unsupported" });
  });

  it("the first deploy plus the migration reaches the next design in Postgres", async () => {
    const next: CreateDesign = {
      appTables: {
        notes: {
          columns: {
            title: { type: "text", nullable: false },
            body: { type: "text" },
          },
        },
      },
    };

    const plan = migrationBetween(code, notes, next);

    if (!plan.ok) {
      throw new Error("expected a migration");
    }

    const result = await validateDesign([
      ...previewFiles(code, notes),
      { path: "migration.sql", module: "app-tables", contents: plan.sql },
    ]);

    expect(result.issues).toEqual([]);
  }, 60_000);
});
