import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  ownLayout,
  snapshotColumnTypes,
  sqlPlan,
} from "../../src/cli/sql-layout.ts";
import { resolveConfig } from "../../src/config/index.ts";
import { moduleSnapshotFixture } from "./fixtures/library.ts";

describe("sql layout edges", () => {
  it("resolves removals under the project root", () => {
    const root = mkdtempSync(join(tmpdir(), "bsb-plan-"));
    const config = resolveConfig({}, root);

    const plan = sqlPlan(config, {
      regenerate: "better-supabase upgrade",
      files: [{ path: "supabase/schemas/app.sql", contents: "" }],
      remove: [
        "supabase/schemas/old.sql",
        { path: "supabase/schemas/kept.sql", keep: () => "hand edited" },
      ],
    });

    expect(plan.files[0]?.path).toBe(join(root, "supabase/schemas/app.sql"));
    expect(plan.remove?.[0]).toBe(join(root, "supabase/schemas/old.sql"));
    expect(plan.remove?.[1]).toMatchObject({
      path: join(root, "supabase/schemas/kept.sql"),
    });
  });

  it("rejects a snapshot that is not JSON and reads a partial unique index", async () => {
    const root = mkdtempSync(join(tmpdir(), "bsb-snap-"));

    writeFileSync(join(root, "broken.json"), "not json");

    const broken = resolveConfig({}, root);

    const brokenSource = {
      ...broken,
      source: { ...broken.source, snapshot: "broken.json" },
    };

    await expect(snapshotColumnTypes(brokenSource, [])).resolves.toEqual(
      new Map(),
    );
    await expect(
      snapshotColumnTypes(brokenSource, ["public.notes"]),
    ).rejects.toThrow(/JSON|Unexpected token/);

    const snap = structuredClone(moduleSnapshotFixture);

    const tables = snap.extras.tables as unknown as {
      schema: string;
      name: string;
      primaryKey: readonly string[];
      indexes: Record<string, unknown>[];
    }[];

    const table = tables[0];

    if (table === undefined) {
      throw new Error("the module snapshot has no tables");
    }

    table.indexes = [
      ...table.indexes,
      {
        name: "coverage_hash_idx",
        columns: ["id"],
        unique: false,
        primary: false,
        partial: false,
        method: "hash",
        predicate: null,
      },
      {
        name: "coverage_partial_idx",
        columns: ["id"],
        unique: false,
        primary: false,
        partial: true,
        method: "btree",
        predicate: "where false",
      },
      {
        name: "coverage_open_idx",
        columns: [table.primaryKey[0] ?? "id"],
        unique: true,
        primary: false,
        partial: true,
        method: "btree",
        predicate: `where "${table.primaryKey[0] ?? "id"}" is not null`,
      },
      {
        name: "coverage_plain_idx",
        columns: [table.primaryKey[0] ?? "id"],
        unique: true,
        primary: false,
        partial: true,
        method: "btree",
        predicate: `where (${table.primaryKey[0] ?? "id"} is not null)`,
      },
      {
        name: "coverage_miss_idx",
        columns: ["id"],
        unique: true,
        primary: false,
        partial: true,
        method: "btree",
        predicate: "where true",
      },
    ];
    writeFileSync(join(root, "snap.json"), JSON.stringify(snap));

    const config = {
      ...resolveConfig({}, root),
      schemas: [...new Set(tables.map((entry) => entry.schema))],
    };

    const layout = await ownLayout({
      ...config,
      source: { ...config.source, snapshot: "snap.json" },
    });

    const indexes = layout.ownIndexes?.[`${table.schema}.${table.name}`] ?? [];

    expect(indexes.map((index) => index.name)).toContain("coverage_open_idx");
    expect(indexes.map((index) => index.name)).toContain("coverage_plain_idx");
    expect(indexes.map((index) => index.name)).not.toContain(
      "coverage_hash_idx",
    );
    expect(indexes.map((index) => index.name)).not.toContain(
      "coverage_miss_idx",
    );
  });
});
