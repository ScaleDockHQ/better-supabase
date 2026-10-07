import { describe, expect, it } from "vitest";

import type { BetterSupabaseConfig } from "../../../src/config/index.ts";
import type { Snapshot } from "../../../src/config/snapshot.ts";

import { emitModule } from "../../../src/cli/gen/emit.ts";
import { buildModel } from "../../../src/cli/gen/model.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { libraryFixture } from "../fixtures/library.ts";
import { loadFixtureSnapshot } from "../fixtures/render.ts";

const root = libraryFixture("").pathname;
const BOTH = ["public", "better_supabase"];

type Generator = Snapshot["generator"];
type Edit = (generator: Generator) => Partial<Generator>;

async function model(edit: Edit, config: BetterSupabaseConfig = {}) {
  const fixture = await loadFixtureSnapshot();
  const snapshot: Snapshot = {
    ...fixture,
    generator: { ...fixture.generator, ...edit(fixture.generator) },
  };
  return buildModel(
    snapshot,
    resolveConfig({ casing: "camel", ...config }, root),
  );
}

const tableNamed = (generator: Generator, name: string) =>
  generator.tables.find(
    (table) => table.schema === "public" && table.name === name,
  )!;

/** A copy of `public.<name>` and its columns under another schema or name. */
const copyTable =
  (name: string, as: { schema?: string; name?: string }): Edit =>
  (generator) => {
    const source = tableNamed(generator, name);
    const id = source.id + 900_000;
    return {
      tables: [
        ...generator.tables,
        {
          ...source,
          id,
          schema: as.schema ?? source.schema,
          name: as.name ?? source.name,
        },
      ],
      columns: [
        ...generator.columns,
        ...generator.columns
          .filter((column) => column.table_id === source.id)
          .map((column) => ({
            ...column,
            table_id: id,
            schema: as.schema ?? column.schema,
            table: as.name ?? column.table,
          })),
      ],
    };
  };

describe("buildModel collisions", () => {
  it("rejects two columns that share a camel-case name", async () => {
    await expect(
      model((generator) => {
        const tags = tableNamed(generator, "tags");
        const column = generator.columns.find(
          (entry) =>
            entry.table_id === tags.id && entry.name === "organization_id",
        )!;
        return {
          columns: [
            ...generator.columns,
            { ...column, name: "organizationId", ordinal_position: 99 },
          ],
        };
      }),
    ).rejects.toThrow(
      /public\.tags: columns "organization_id" and "organizationId" both become "organizationId"/,
    );
  });

  it("rejects two tables that share a model key", async () => {
    await expect(
      model(copyTable("customer_tags", { name: "customerTags" })),
    ).rejects.toThrow(/both generate the model key "customerTags"/);
  });
});

describe("buildModel config keys", () => {
  it("accepts schema.table keys", async () => {
    const built = await model(
      copyTable("tags", { schema: "better_supabase" }),
      {
        schemas: BOTH,
        tables: {
          "better_supabase.tags": { exclude: true },
          tags: { casing: "snake" },
          "nope.tags": {},
        },
      },
    );
    expect(
      built.tables.filter((table) => table.snapshot.name === "tags"),
    ).toHaveLength(1);
    expect(built.tables.find((table) => table.key === "tags")?.casing).toBe(
      "snake",
    );
    expect(built.warnings).toEqual([
      expect.stringContaining('tables["nope.tags"]: no table by that name'),
    ]);
  });

  it("warns about a bare key two schemas share", async () => {
    const built = await model(
      copyTable("tags", { schema: "better_supabase" }),
      {
        schemas: BOTH,
        tables: { tags: { casing: "snake" } },
      },
    );
    expect(built.warnings).toEqual([
      'tables["tags"]: better_supabase.tags and public.tags share the name, so the entry applies to each. Key it `schema.table` to pick one.',
    ]);
  });
});

describe("buildModel functions", () => {
  const addFunction =
    (schema: string, name: string, argType?: number): Edit =>
    (generator) => {
      const template = generator.functions[0]!;
      return {
        functions: [
          ...generator.functions,
          {
            ...template,
            id: template.id + 900_000 + name.length,
            schema,
            name,
            args:
              argType === undefined
                ? []
                : [
                    {
                      mode: "in",
                      name: "kind",
                      type_id: argType,
                      has_default: false,
                    },
                  ],
            identity_argument_types: "",
            return_type: "void",
            return_type_id: -1,
            return_type_relation_id: null,
            is_set_returning_function: false,
          },
        ],
      };
    };

  it("types an enum argument from the enum's own schema", async () => {
    const built = await model(
      (generator) => {
        const kind = generator.types.find((type) => type.name === "note_kind")!;
        return addFunction("better_supabase", "log_kind", kind.id)(generator);
      },
      { schemas: BOTH },
    );
    expect(
      built.functions.find((fn) => fn.key === "log_kind")?.args[0]?.tsType,
    ).toBe('"call" | "meeting" | "email"');
  });

  it("keeps the function from the first schema when a name repeats", async () => {
    const built = await model(
      (generator) => {
        const first = addFunction("better_supabase", "ping")(generator);
        const both = addFunction(
          "public",
          "ping",
        )({
          ...generator,
          functions: first.functions ?? [],
        });
        return {
          functions: (both.functions ?? []).map((fn, index, all) =>
            index === all.length - 1 ? { ...fn, id: fn.id + 1 } : fn,
          ),
        };
      },
      { schemas: BOTH },
    );
    const ping = built.functions.filter((fn) => fn.key === "ping");
    expect(ping.map((fn) => fn.meta.schema)).toEqual(["public"]);
    expect(built.warnings).toContainEqual(
      expect.stringContaining(
        "better_supabase.ping: public.ping has the same name",
      ),
    );
  });

  /** `public.area(side int4)`, `area(label text, scale int4 default)` and `area()`, shuffled. */
  const addOverloads: Edit = (generator) => {
    const template = generator.functions[0]!;
    const typeId = (name: string) =>
      generator.types.find(
        (type) => type.schema === "pg_catalog" && type.name === name,
      )!.id;
    const overload = (
      offset: number,
      signature: string,
      args: { name: string; type: string; has_default: boolean }[],
      returns: string,
    ) => ({
      ...template,
      id: template.id + 910_000 + offset,
      schema: "public",
      name: "area",
      args: args.map((arg) => ({
        mode: "in" as const,
        name: arg.name,
        type_id: typeId(arg.type),
        has_default: arg.has_default,
      })),
      argument_types: signature,
      identity_argument_types: signature,
      return_type: returns,
      return_type_id: typeId(returns),
      return_type_relation_id: null,
      is_set_returning_function: false,
    });
    return {
      functions: [
        ...generator.functions,
        overload(
          1,
          "label text, scale integer",
          [
            { name: "label", type: "text", has_default: false },
            { name: "scale", type: "int4", has_default: true },
          ],
          "text",
        ),
        overload(2, "", [], "bool"),
        overload(
          3,
          "side integer",
          [{ name: "side", type: "int4", has_default: false }],
          "int4",
        ),
      ],
    };
  };

  it("keeps every overload, in signature order", async () => {
    const built = await model(addOverloads);
    expect(
      built.functions
        .filter((fn) => fn.key === "area")
        .map((fn) => fn.args.map((arg) => arg.name)),
    ).toEqual([[], ["label", "scale"], ["side"]]);
    expect(built.meta.functions["area"]).toEqual({
      name: "area",
      schema: "public",
      args: [],
      returns: "bool",
      returnsSet: false,
      volatility: built.meta.functions["area"]?.volatility,
      overloads: [
        expect.objectContaining({ args: [], returns: "bool" }),
        expect.objectContaining({
          args: [
            { name: "label", type: "text" },
            { name: "scale", type: "int4", optional: true },
          ],
          returns: "text",
        }),
        expect.objectContaining({
          args: [{ name: "side", type: "int4" }],
          returns: "int4",
        }),
      ],
    });
  });

  it("emits a union of Args and Returns for an overloaded function", async () => {
    const built = await model(addOverloads);
    const reversed = await model((generator) => {
      const edited = addOverloads(generator);
      return { functions: [...(edited.functions ?? [])].reverse() };
    });
    const emit = (input: typeof built) =>
      emitModule(input, { importPathFor: (from) => from });
    const source = emit(built);
    expect(emit(reversed)).toBe(source);
    const area = source.slice(
      source.indexOf("area:"),
      source.indexOf("};", source.lastIndexOf("Returns: number | null;")) + 2,
    );
    expect(area).toBe(
      [
        "area:",
        "  | {",
        "    Args: Record<PropertyKey, never>;",
        "    Returns: boolean | null;",
        "  }",
        "  | {",
        "    Args: {",
        "      label: string | null;",
        "      scale?: number | null;",
        "    };",
        "    Returns: string | null;",
        "  }",
        "  | {",
        "    Args: {",
        "      side: number | null;",
        "    };",
        "    Returns: number | null;",
        "  };",
      ].join("\n  "),
    );
  });
});

describe("buildModel enums", () => {
  it("prefixes a non-public enum that repeats a public enum's name", async () => {
    const built = await model(
      (generator) => {
        const kind = generator.types.find((type) => type.name === "note_kind")!;
        return {
          types: [
            ...generator.types,
            {
              ...kind,
              id: kind.id + 900_000,
              schema: "better_supabase",
              enums: ["a", "b"],
            },
          ],
        };
      },
      { schemas: BOTH },
    );
    expect(
      built.enums.map((entry) => [entry.key, entry.constant, entry.typeName]),
    ).toEqual(
      expect.arrayContaining([
        ["note_kind", "noteKindValues", "NoteKind"],
        [
          "better_supabase_note_kind",
          "betterSupabaseNoteKindValues",
          "BetterSupabaseNoteKind",
        ],
      ]),
    );
    expect(Object.keys(built.meta.enums)).toEqual(
      expect.arrayContaining(["note_kind", "better_supabase_note_kind"]),
    );
  });

  it("turns an enum name into a valid identifier and rejects reserved ones", async () => {
    const withEnum = (name: string) =>
      model((generator) => {
        const kind = generator.types.find((type) => type.name === "note_kind")!;
        return {
          types: [
            ...generator.types,
            { ...kind, id: kind.id + 900_000, name, enums: ["x"] },
          ],
        };
      });
    const odd = await withEnum("2fa level");
    expect(odd.enums.find((entry) => entry.name === "2fa level")).toMatchObject(
      { constant: "_2fa_levelValues", typeName: "_2fa_level" },
    );

    const reserved = await withEnum("schema");
    expect(() =>
      emitModule(reserved, { importPathFor: (from) => from }),
    ).toThrow(
      /enum public\.schema and the generated module both export "Schema"/,
    );
  });
});
