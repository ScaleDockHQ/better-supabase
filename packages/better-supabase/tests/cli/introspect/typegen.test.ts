import { describe, expect, it } from "vitest";

import {
  type GeneratorMetadata,
  generatorJsonSchema,
  orderArgsByPosition,
  readGeneratorMetadata,
  restrictSchemas,
  serializeGenerator,
  stabilizeMetadata,
  tsTypeOf,
  validateGeneratorMetadata,
} from "../../../src/cli/introspect/typegen.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const generator = await validateGeneratorMetadata(fixture.generator);

type TypeRow = GeneratorMetadata["types"][number];
const type = (
  id: number,
  schema: string,
  name: string,
  attributes: number[] = [],
): TypeRow => ({
  id,
  name,
  schema,
  format: name,
  enums: [],
  attributes: attributes.map((typeId, index) => ({
    name: `a${index}`,
    type_id: typeId,
  })),
  comment: null,
  type_relation_id: null,
});

const column = (format: string, typeSchema: string) => ({
  table_id: 20000,
  schema: "public",
  table: "notes",
  id: "20000.1",
  ordinal_position: 1,
  name: format,
  default_value: null,
  data_type: format,
  format,
  type_schema: typeSchema,
  is_identity: false,
  identity_generation: null,
  is_generated: false,
  is_nullable: true,
  is_updatable: true,
  is_unique: false,
  enums: [],
  check: null,
  comment: null,
});

describe("readGeneratorMetadata", () => {
  it("keeps the types the read schemas reference and drops the rest", async () => {
    const db = fakeSql([
      [
        "sane arg_modes",
        [
          {
            id: "30000",
            schema: "public",
            name: "make_address",
            return_type: "node",
            return_type_id: "300",
            args: [{ mode: "in", name: "a", type_id: 200, has_default: false }],
          },
          {
            id: 30001,
            schema: "public",
            name: "touch",
            return_type: "trigger",
            return_type_id: 16,
            args: [],
          },
        ],
      ],
      [
        "Adapted from information_schema.columns",
        [
          column("int4", "pg_catalog"),
          column("_text", "pg_catalog"),
          column("mood", "public"),
          column("missing", "pg_catalog"),
        ],
      ],
      [
        "t_enums",
        [
          type(100, "public", "mood"),
          type(23, "pg_catalog", "int4"),
          type(25, "pg_catalog", "text"),
          type(1009, "pg_catalog", "_text"),
          type(200, "extensions", "address", [25, 999]),
          type(300, "extensions", "node", [300]),
          type(16, "pg_catalog", "bool"),
          type(700, "extensions", "unused"),
        ],
      ],
    ]);
    const metadata = await readGeneratorMetadata(db.pg, ["public"]);
    expect(
      db.texts().some((text) => text.includes("p.proargnames as names")),
    ).toBe(true);
    expect(
      metadata.types.map((entry) => entry.id).sort((a, b) => a - b),
    ).toEqual([23, 25, 100, 200, 300, 1009]);
    expect(metadata.functions.map((fn) => fn.name)).toEqual(["make_address"]);
    expect(metadata.functions[0]!.id).toBe(30000);
    expect(db.calls.length).toBeGreaterThan(5);
  });
});

describe("orderArgsByPosition", () => {
  const arg = (name: string, typeId: number) => ({
    mode: "in" as const,
    name,
    type_id: typeId,
    has_default: false,
  });
  const fn = (args: ReturnType<typeof arg>[]) => ({
    ...generator.functions[0]!,
    id: 40000,
    name: "l2_distance",
    args,
  });

  it("restores declaration order for unnamed arguments", () => {
    const shuffled = fn([arg("", 20), arg("", 10)]);
    const metadata = { ...generator, functions: [shuffled] };
    const ordered = orderArgsByPosition(metadata, [
      { id: "40000", types: ["10", "20"], names: null },
    ]);
    expect(ordered.functions[0]!.args.map((entry) => entry.type_id)).toEqual([
      10, 20,
    ]);
    const twice = orderArgsByPosition(
      { ...generator, functions: [fn([arg("", 10), arg("", 20)])] },
      [{ id: 40000, types: [10, 20], names: null }],
    );
    expect(twice.functions[0]!.args).toEqual(ordered.functions[0]!.args);
  });

  it("keeps arguments it can't place and functions it has no row for", () => {
    const named = fn([arg("b", 20), arg("a", 10), arg("", 30)]);
    const metadata = { ...generator, functions: [named] };
    const ordered = orderArgsByPosition(metadata, [
      { id: 40000, types: [10, 20], names: ["a", "b"] },
    ]);
    expect(ordered.functions[0]!.args.map((entry) => entry.name)).toEqual([
      "a",
      "b",
      "",
    ]);
    expect(orderArgsByPosition(metadata, []).functions[0]).toBe(named);
  });
});

describe("stabilizeMetadata", () => {
  it("maps views, foreign tables, types and function references to name-derived ids", () => {
    const base = structuredClone(generator);
    const metadata: GeneratorMetadata = {
      ...base,
      tables: [],
      columns: [],
      primaryKeys: [],
      schemas: [{ id: 50000, name: "public", owner: "postgres" }],
      views: [
        {
          id: 40001,
          schema: "public",
          name: "b_view",
          comment: null,
          is_updatable: false,
        },
      ],
      foreignTables: [
        { id: 40002, schema: "public", name: "a_remote", comment: null },
      ],
      materializedViews: [
        {
          id: 40003,
          schema: "public",
          name: "c_mat",
          comment: null,
          is_populated: true,
        },
      ],
      types: [
        {
          ...type(41000, "public", "row_type", [23, 41001]),
          type_relation_id: 40001,
        },
        type(41001, "public", "addr"),
        type(23, "pg_catalog", "int4"),
      ],
      functions: [
        {
          ...base.functions[0]!,
          id: 42000,
          schema: "public",
          name: "f",
          identity_argument_types: "",
          return_type_id: 41000,
          return_type_relation_id: null,
          args: [{ mode: "in", name: "x", type_id: 41001, has_default: false }],
        },
      ],
    };
    const { metadata: stable, ids } = stabilizeMetadata(metadata);
    expect(Object.fromEntries(ids)).toEqual({
      40002: 1_000_000,
      40001: 1_000_001,
      40003: 1_000_002,
      41001: 2_000_001,
      41000: 2_000_002,
      42000: 3_000_000,
      50000: 4_000_000,
    });
    expect(stable.views[0]!.id).toBe(1_000_001);
    expect(stable.foreignTables[0]!.id).toBe(1_000_000);
    expect(stable.materializedViews[0]!.id).toBe(1_000_002);
    const rowType = stable.types.find((entry) => entry.name === "row_type")!;
    expect(rowType.type_relation_id).toBe(1_000_001);
    expect(rowType.attributes.map((attribute) => attribute.type_id)).toEqual([
      23, 2_000_001,
    ]);
    expect(stable.types.find((entry) => entry.name === "int4")!.id).toBe(23);
    expect(stable.functions[0]).toMatchObject({
      id: 3_000_000,
      return_type_id: 2_000_002,
      return_type_relation_id: null,
      args: [{ type_id: 2_000_001 }],
    });
  });

  it("zeroes table sizes and maps function return relations", () => {
    const shifted = structuredClone(generator);
    const table = shifted.tables[0]!;
    table.bytes = 8192;
    table.live_rows_estimate = 12;
    shifted.functions[0]!.return_type_relation_id = table.id;
    const { metadata } = stabilizeMetadata(shifted);
    expect(
      metadata.tables.every(
        (entry) =>
          entry.bytes === 0 &&
          entry.size === "0 bytes" &&
          entry.live_rows_estimate === 0,
      ),
    ).toBe(true);
    expect(
      metadata.functions.find((fn) => fn.name === shifted.functions[0]!.name)
        ?.return_type_relation_id,
    ).toBe(table.id);
  });
});

describe("restrictSchemas", () => {
  it("keeps only the listed schemas", () => {
    const only = restrictSchemas(generator, ["public"]);
    expect(only.schemas.map((schema) => schema.name)).toEqual(["public"]);
    for (const list of [
      only.tables,
      only.columns,
      only.primaryKeys,
      only.relationships,
      only.functions,
    ]) {
      expect(list.length).toBeGreaterThan(0);
      expect(list.every((entry) => entry.schema === "public")).toBe(true);
    }
    expect(only.tables.length).toBeLessThan(generator.tables.length);
    expect(restrictSchemas(generator, []).tables).toEqual([]);
  });

  it("filters views, materialized views and foreign tables by schema", () => {
    const relation = (schema: string, name: string) => ({
      id: 1,
      schema,
      name,
      comment: null,
      is_updatable: false,
      is_populated: true,
    });
    const metadata = {
      ...generator,
      views: [relation("public", "v"), relation("private", "v")],
      materializedViews: [relation("private", "m"), relation("public", "m")],
      foreignTables: [relation("private", "f"), relation("public", "f")],
    } as GeneratorMetadata;
    const only = restrictSchemas(metadata, ["public"]);
    for (const list of [only.views, only.materializedViews, only.foreignTables])
      expect(list.map((entry) => entry.schema)).toEqual(["public"]);
  });
});

describe("generator documents", () => {
  it("serializes metadata that validates again", async () => {
    const text = await serializeGenerator(generator);
    const parsed = await validateGeneratorMetadata(JSON.parse(text));
    expect(await serializeGenerator(parsed)).toBe(text);
    expect(parsed.tables.length).toBe(generator.tables.length);
  });

  it("rejects metadata that does not match the contract", async () => {
    await expect(validateGeneratorMetadata({ version: 1 })).rejects.toThrow(
      /^Invalid GeneratorMetadata: columns must be an array \(was missing\)\n/,
    );
  });

  it("embeds the contract's JSON Schema without its dialect", async () => {
    const schema = await generatorJsonSchema();
    expect(schema).not.toHaveProperty("$schema");
    expect(schema["type"]).toBe("object");
  });
});

describe("tsTypeOf", () => {
  it("resolves built-ins, enums and arrays like the Database type", () => {
    expect(tsTypeOf(generator, "public", "int4")).toBe("number");
    expect(tsTypeOf(generator, "nowhere", "text")).toBe("string");
    expect(tsTypeOf(generator, "public", "_text")).toBe("(string)[]");
  });
});
