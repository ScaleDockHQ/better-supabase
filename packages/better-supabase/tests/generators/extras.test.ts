import { describe, expect, it } from "vitest";

import type { GeneratorBlock, GeneratorInput } from "../../src/config/index.ts";
import type { ColumnMeta } from "../../src/schema/types.ts";

import { resolveConfig } from "../../src/config/index.ts";
import { jsonSchema } from "../../src/generators/json-schema.ts";
import { standardSchema } from "../../src/generators/standard-schema.ts";
import { valibot } from "../../src/generators/valibot.ts";
import { zod } from "../../src/generators/zod.ts";
import { PRESET_CATALOG } from "../../src/preset/catalog.generated.ts";
import { snapshotFixture } from "../cli/fixtures/library.ts";

const column = (
  db: string,
  type: string,
  extra: Partial<ColumnMeta> = {},
): ColumnMeta => ({ db, type, nullable: false, hasDefault: false, ...extra });

const workItems = PRESET_CATALOG.manifests.find(
  (manifest) => manifest.name === "tasks",
);

const taskBlock: GeneratorBlock = {
  name: "tasks",
  schema: "work_items",
  client: { export: "tasksBlock", subpath: "better-supabase/blocks/tasks" },
  entities: [
    {
      key: "task",
      from: { singular: "work_item", plural: "work_items" },
      to: { singular: "task", plural: "tasks" },
      primary: true,
      table: "tasks",
      url: undefined,
      schemas: workItems?.entitySchemas?.["task"] ?? {},
    },
  ],
};

const config = resolveConfig(
  { gen: { output: "src/generated.ts" } },
  "/project",
);

const input: GeneratorInput = {
  meta: {
    version: 1,
    casing: "camel",
    enums: { "public.priority": ["low", "high"] },
    functions: {
      list_notes: {
        name: "list_notes",
        schema: "public",
        args: [
          { name: "since", type: "timestamptz" },
          { name: "tags", type: "text" },
          { name: "level", type: "priority" },
        ],
        returns: "notes",
        returnsSet: true,
        volatility: "stable",
      },
      note_count: {
        name: "note_count",
        schema: "public",
        args: [{ name: "owner", type: "uuid" }],
        returns: "int4",
        returnsSet: false,
        volatility: "stable",
      },
      rebuild: {
        name: "rebuild",
        schema: "public",
        args: [],
        returns: "void",
        returnsSet: false,
        volatility: "volatile",
      },
    },
    tables: {
      notes: {
        key: "notes",
        name: "notes",
        schema: "public",
        kind: "table",
        columns: {
          id: column("id", "uuid", { hasDefault: true }),
          title: column("title", "text"),
          level: column("level", "priority", { enum: ["low", "high"] }),
        },
        primaryKey: ["id"],
        uniqueKeys: {},
        relations: {},
        flags: {},
      },
    },
  },
  introspection: snapshotFixture.generator,
  extras: { tables: [], buckets: [], realtime: [] },
  config,
  output: "/project/src/generated.ts",
  importPath: () => "./generated.ts",
  model: {
    tables: [],
    enums: [],
    functions: [
      {
        key: "list_notes",
        schema: "public",
        args: [
          {
            name: "since",
            tsType: "string",
            optional: false,
            values: undefined,
          },
          {
            name: "tags",
            tsType: "string[]",
            optional: true,
            values: undefined,
          },
          {
            name: "level",
            tsType: '"low" | "high"',
            optional: false,
            values: ["low", "high"],
          },
        ],
        returns: "Models[\"notes\"]['Row'][]",
        returnsSet: true,
        volatility: "stable",
      },
      {
        key: "note_count",
        schema: "public",
        args: [
          {
            name: "owner",
            tsType: "string",
            optional: false,
            values: undefined,
          },
        ],
        returns: "number | null",
        returnsSet: false,
        volatility: "stable",
      },
      {
        key: "rebuild",
        schema: "public",
        args: [],
        returns: "unknown",
        returnsSet: false,
        volatility: "volatile",
      },
    ],
    blocks: [taskBlock],
  },
};

const lines = (text: string) => text.split("\n");

describe("function and block schemas", () => {
  it("has the tasks input schemas in the catalog", () => {
    expect(taskBlock.entities[0]?.schemas.input?.title).toBe("WorkItemInput");
  });

  it("writes zod schemas for arguments, results and renamed block inputs", async () => {
    const [file] = await zod({ fieldMeta: true }).generate(input);
    const text = lines(file!.contents);

    expect(text).toEqual(
      expect.arrayContaining([
        'export const listNotesArgs: z.ZodType<{ since: string; tags?: string[]; level: "low" | "high" }> = z.object({',
        "  since: z.iso.datetime({ offset: true }),",
        "  tags: z.array(z.string()).exactOptional(),",
        '  level: z.enum(["low", "high"]),',
        "export const noteCountArgs: z.ZodType<{ owner: string }> = z.object({",
        "  owner: z.guid(),",
        "export const listNotesResult: z.ZodType<RowOf<'notes'>[]> = z.array(notesRow);",
        "export const noteCountResult: z.ZodType<number | null> = z.int().nullable();",
      ]),
    );
    expect(file!.contents).not.toContain("rebuildArgs");
    expect(file!.contents).not.toContain("rebuildResult");

    const taskInput = text.find((line) =>
      line.startsWith("export const taskInput:"),
    );

    expect(taskInput).toContain("title: string");
    expect(taskInput).toContain("Temporal.Instant");
    expect(file!.contents).toContain('.meta({ title: "TaskInput" })');
    expect(file!.contents).toContain("export const taskChange:");
    expect(file!.contents).toContain("  taskId: z.guid(),");
    expect(file!.contents).toContain("export const taskListFilter:");
    expect(file!.contents).not.toMatch(/workItem|WorkItem/);
    expect(file!.contents).toContain(
      'import { isInstant } from "better-supabase";',
    );

    expect(file!.contents).toContain("export const fieldMeta = {");
    expect(text).toContain(
      '    level: {"label":"Level","required":true,"options":["low","high"]},',
    );
    expect(text).toContain('    id: {"label":"Id","required":false},');
    expect(text).toContain('    taskId: {"label":"Task id","required":true},');
  });

  it("leaves fieldMeta out unless asked", async () => {
    const [file] = await zod().generate(input);
    expect(file!.contents).not.toContain("fieldMeta");
  });

  it("writes the same schemas with zod/mini", async () => {
    const [file] = await zod({ flavor: "mini" }).generate(input);
    expect(file!.contents).toContain(
      "export const noteCountResult: z.ZodMiniType<number | null> = z.nullable(z.int());",
    );
    expect(file!.contents).toContain(
      "  tags: z.exactOptional(z.array(z.string())),",
    );
  });

  it("writes valibot schemas", async () => {
    const [file] = await valibot({ fieldMeta: true }).generate(input);
    const text = lines(file!.contents);

    expect(text).toEqual(
      expect.arrayContaining([
        "export const noteCountArgs: v.GenericSchema<{ owner: string }> = v.pipe(v.object({",
        "  owner: v.pipe(v.string(), v.uuid()),",
        '}), v.title("note_count arguments"));',
        "export const listNotesResult: v.GenericSchema<RowOf<'notes'>[]> = v.array(notesRow);",
        "export const noteCountResult: v.GenericSchema<number | null> = v.nullable(v.pipe(v.number(), v.integer()));",
      ]),
    );
    expect(file!.contents).toContain("export const taskInput:");
    expect(file!.contents).toContain("export const fieldMeta = {");
  });

  it("writes Standard Schemas for the inputs", async () => {
    const [file] = await standardSchema().generate(input);
    expect(file!.contents).toContain(
      "export const noteCountArgs: TableSchema<{ owner: string }> = tableSchema({",
    );
    expect(file!.contents).toContain('    owner: {"kind":"uuid"},');
    expect(file!.contents).toContain('  title: "TaskInput",');
    expect(file!.contents).not.toContain("Result");
  });

  it("writes JSON Schema defs with labels when fieldMeta is on", async () => {
    const [file] = await jsonSchema({ fieldMeta: true }).generate(input);

    const doc = JSON.parse(file!.contents) as {
      $defs: Record<string, Record<string, unknown>>;
    };

    expect(doc.$defs["listNotesResult"]).toEqual({
      title: "list_notes result",
      type: "array",
      items: { $ref: "#/$defs/notesRow" },
    });
    expect(doc.$defs["noteCountResult"]).toEqual({
      title: "note_count result",
      type: ["integer", "null"],
    });
    expect(doc.$defs["noteCountArgs"]).toMatchObject({
      required: ["owner"],
      properties: { owner: { title: "Owner", type: "string", format: "uuid" } },
    });
    expect(doc.$defs["notesInsert"]).toMatchObject({
      properties: { title: { title: "Title", type: "string" } },
    });
    expect(doc.$defs["taskInput"]).toMatchObject({ title: "TaskInput" });
  });

  it("lowers result refs for draft-07", async () => {
    const [file] = await jsonSchema({ target: "draft-07" }).generate(input);
    expect(file!.contents).toContain('"$ref": "#/definitions/notesRow"');
  });
});
