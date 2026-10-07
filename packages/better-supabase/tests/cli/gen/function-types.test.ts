import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import type { Snapshot } from "../../../src/cli/introspect/types.ts";

import { buildModel } from "../../../src/cli/gen/model.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { libraryFixture } from "../fixtures/library.ts";
import { loadFixtureSnapshot } from "../fixtures/render.ts";

const fixtures = fileURLToPath(libraryFixture(""));
const config = resolveConfig({ casing: "camel" }, fixtures);

async function withGenerator(
  change: (generator: Snapshot["generator"]) => void,
): Promise<Snapshot> {
  const snapshot = structuredClone(await loadFixtureSnapshot());
  change(snapshot.generator);
  return snapshot;
}

describe("view columns", () => {
  it("keeps a computed view column out of inserts and updates", async () => {
    const snapshot = await withGenerator((generator) => {
      const notes = generator.tables.find((table) => table.name === "notes")!;
      const id = 1_999_001;
      generator.views.push({
        id,
        schema: "public",
        name: "note_view",
        is_updatable: true,
        comment: null,
      });
      for (const column of generator.columns.filter(
        (entry) => entry.table_id === notes.id,
      )) {
        generator.columns.push({
          ...column,
          table_id: id,
          table: "note_view",
          id: `${id}.${column.ordinal_position}`,
          is_updatable: column.name !== "body",
        });
      }
    });
    const view = buildModel(snapshot, config).tables.find(
      (table) => table.key === "noteView",
    );
    const column = (name: string) =>
      view?.columns.find((entry) => entry.db === name);
    expect(column("body")).toMatchObject({
      insertable: false,
      updatable: false,
    });
    expect(column("customer_id")).toMatchObject({
      insertable: true,
      updatable: true,
    });
  });
});

describe("function types", () => {
  it("resolves argument and return types in the type's own schema", async () => {
    const snapshot = await withGenerator((generator) => {
      const enumType = (id: number, schema: string, values: string[]) => ({
        id,
        name: "mood",
        schema,
        format: "mood",
        enums: values,
        attributes: [],
        comment: null,
        type_relation_id: null,
      });
      generator.types.push(
        enumType(1_999_100, "public", ["plain"]),
        enumType(1_999_101, "better_supabase", ["calm", "busy"]),
      );
      const template = generator.functions.find(
        (fn) => fn.name === "purge_rate_limits",
      )!;
      generator.functions.push({
        ...template,
        id: 1_999_200,
        schema: "public",
        name: "next_mood",
        args: [
          {
            mode: "in",
            name: "current",
            type_id: 1_999_101,
            has_default: false,
          },
        ],
        argument_types: "current better_supabase.mood",
        identity_argument_types: "current better_supabase.mood",
        return_type_id: 1_999_101,
        return_type: "better_supabase.mood",
      });
    });
    const fn = buildModel(snapshot, config).functions.find(
      (entry) => entry.key === "next_mood",
    );
    expect(fn?.args[0]?.tsType).toBe('"calm" | "busy"');
    expect(fn?.returns).toBe('"calm" | "busy" | null');
  });
});
