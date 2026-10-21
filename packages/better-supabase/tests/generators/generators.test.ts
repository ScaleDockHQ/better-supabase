import { readFile } from "node:fs/promises";
import { dirname, relative, resolve, sep } from "node:path";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { GeneratorInput } from "../../src/config/index.ts";
import type { ColumnMeta, TableMeta } from "../../src/schema/types.ts";

import { resolveConfig } from "../../src/config/index.ts";
import {
  buildJsonSchema,
  jsonSchema,
} from "../../src/generators/json-schema.ts";
import { standardSchema } from "../../src/generators/standard-schema.ts";
import { valibot } from "../../src/generators/valibot.ts";
import { zod } from "../../src/generators/zod.ts";
import { snapshotFixture } from "../cli/fixtures/library.ts";
import * as standardSchemas from "../fixtures/generated-camel.standard.ts";
import * as valibotSchemas from "../fixtures/generated-camel.valibot.ts";
import * as zodMiniSchemas from "../fixtures/generated-camel.zod-mini.ts";
import * as zodSchemas from "../fixtures/generated-camel.zod.ts";

function importPath(fromFile: string, toFile: string): string {
  const path = relative(dirname(fromFile), toFile).split(sep).join("/");

  return path.startsWith(".") ? path : `./${path}`;
}

const customer = {
  organizationId: "00000000-0000-4000-8000-000000000001",
  name: "Acme",
  status: "active",
  createdAt: "2026-09-24T09:35:10.123456+00:00",
};

describe("zod generator", () => {
  it("accepts valid inserts and strips nothing required", () => {
    expect(zodSchemas.customersInsert.parse(customer)).toEqual(customer);
  });

  it("rejects values outside CHECK unions and bad uuids", () => {
    const result = zodSchemas.customersInsert.safeParse({
      ...customer,
      status: "deleted",
      organizationId: "x",
    });

    expect(result.success).toBe(false);
    expect(
      result.error?.issues.map((issue) => issue.path.join(".")).toSorted(),
    ).toEqual(["organizationId", "status"]);
  });

  it("leaves generated identity columns out of writes", () => {
    const note = {
      organizationId: customer.organizationId,
      customerId: customer.organizationId,
      body: "hi",
    };

    expect(zodSchemas.notesInsert.parse({ ...note, id: 5 })).toEqual(note);
    expect(
      zodSchemas.notesRow.safeParse({
        ...note,
        kind: "call",
        attachments: null,
      }).success,
    ).toBe(false);
  });

  it("exposes Standard Schema validators for the validation plugin", () => {
    expect(zodSchemas.validators.customers.insert["~standard"].vendor).toBe(
      "zod",
    );
  });
});

describe("zod generator, mini flavor", () => {
  it("validates the same shapes with zod/mini", () => {
    expect(zodMiniSchemas.customersInsert.parse(customer)).toEqual(customer);

    const result = zodMiniSchemas.customersInsert.safeParse({
      ...customer,
      status: "deleted",
      organizationId: "x",
    });

    expect(
      result.error?.issues.map((issue) => issue.path.join(".")).toSorted(),
    ).toEqual(["organizationId", "status"]);
    expect(
      zodMiniSchemas.customersInsert.safeParse({ ...customer, name: "" })
        .success,
    ).toBe(false);
  });

  it("exposes Standard Schema validators for the validation plugin", () => {
    expect(zodMiniSchemas.validators.customers.insert["~standard"].vendor).toBe(
      "zod",
    );
  });
});

describe("valibot generator", () => {
  it("validates the same shapes", () => {
    expect(v.parse(valibotSchemas.customersInsert, customer)).toEqual(customer);
    expect(
      v.safeParse(valibotSchemas.customersInsert, {
        ...customer,
        status: "deleted",
      }).success,
    ).toBe(false);
    expect(
      v.safeParse(valibotSchemas.notesInsert, {
        organizationId: customer.organizationId,
        customerId: customer.organizationId,
        body: "hi",
        attachments: { files: [{ name: "a.pdf", size: 1 }] },
      }).success,
    ).toBe(true);
  });
});

describe("standard schema generator", () => {
  it("validates the same shapes without a validation library", () => {
    const props = standardSchemas.customersInsert["~standard"];
    expect(props.vendor).toBe("better-supabase");
    expect(props.validate({ ...customer, extra: 1 })).toEqual({
      value: customer,
    });

    const bad = props.validate({
      ...customer,
      status: "deleted",
      organizationId: "x",
    });

    expect(
      !(bad instanceof Promise) &&
        bad.issues?.map((issue) => issue.path?.join(".")).toSorted(),
    ).toEqual(["organizationId", "status"]);
  });

  it("leaves generated identity columns out of writes", () => {
    const note = {
      organizationId: customer.organizationId,
      customerId: customer.organizationId,
      body: "hi",
    };

    expect(
      standardSchemas.notesInsert["~standard"].validate({ ...note, id: 5 }),
    ).toEqual({ value: note });
  });

  it("converts to the same JSON Schema the json-schema generator writes", async () => {
    const doc = JSON.parse(
      await readFile(
        new URL("../fixtures/generated-camel.schema.json", import.meta.url),
        "utf-8",
      ),
    ) as { $defs: Record<string, Record<string, unknown>> };

    const { validators: _, ...schemas } = standardSchemas;

    for (const [name, schema] of Object.entries(schemas)) {
      expect(
        schema["~standard"].jsonSchema.input({ target: "draft-2020-12" }),
      ).toEqual({
        $schema: "https://json-schema.org/draft/2020-12/schema",
        ...doc.$defs[name],
      });
    }
  });

  it("exposes validators for the validation plugin", () => {
    expect(standardSchemas.validators.customers.insert).toBe(
      standardSchemas.customersInsert,
    );
  });
});

describe("json schema generator", () => {
  it("writes $defs with required columns and nullable types", async () => {
    const doc = JSON.parse(
      await readFile(
        new URL("../fixtures/generated-camel.schema.json", import.meta.url),
        "utf-8",
      ),
    ) as {
      $defs: Record<
        string,
        { required?: string[]; properties: Record<string, unknown> }
      >;
    };

    const insert = doc.$defs["customersInsert"];
    expect(insert?.required).toEqual(["organizationId", "name"]);
    expect(insert?.properties["status"]).toEqual({
      type: "string",
      enum: ["lead", "active", "archived"],
    });
    expect(insert?.properties["kvk"]).toEqual({
      type: ["string", "null"],
      description: "Chamber of Commerce (KvK) number.",
      examples: ["12345678"],
    });
    expect(doc.$defs["customersRow"]?.properties["archivedAt"]).toEqual({
      type: ["string", "null"],
      format: "date-time",
      readOnly: true,
    });
    expect(insert?.properties["name"]).not.toHaveProperty("readOnly");
  });
});

const column = (
  db: string,
  type: string,
  extra: Partial<ColumnMeta> = {},
): ColumnMeta => ({ db, type, nullable: false, hasDefault: false, ...extra });

const tableMeta = (
  key: string,
  name: string,
  columns: Record<string, ColumnMeta>,
  kind: TableMeta["kind"] = "table",
): TableMeta => ({
  key,
  name,
  schema: "public",
  kind,
  columns,
  primaryKey: [],
  uniqueKeys: {},
  relations: {},
  flags: {},
});

const root = "/project";

const config = resolveConfig(
  {
    output: "src/generated.ts",
    json: { "events.meta": { type: "{ a: number }" } },
  },
  root,
);

const input: GeneratorInput = {
  meta: {
    version: 1,
    casing: "camel",
    enums: {},
    functions: {},
    tables: {
      events: tableMeta("events", "events", {
        id: column("id", "int8", {
          hasDefault: true,
          identity: "always",
          insertable: false,
          updatable: false,
        }),
        amount: column("amount", "numeric", { nullable: true }),
        big: column("big", "int8", { codec: "bigint" }),
        exact: column("exact", "numeric", { codec: "string" }),
        at: column("at", "timestamptz", { codec: "instant" }),
        local: column("local", "timestamp", { codec: "plainDateTime" }),
        day: column("day", "date"),
        flag: column("flag", "bool", { hasDefault: true }),
        labels: column("labels", "text", { array: true }),
        payload: column("payload", "jsonb", { json: true }),
        meta: column("meta", "jsonb", { json: true }),
        raw: column("raw", "jsonb", { json: true }),
        rec: column("rec", "record"),
        total: column("total", "int4", { generated: true }),
        "odd-name": column("odd-name", "text"),
      }),
      eventView: tableMeta(
        "eventView",
        "event_view",
        { id: column("id", "int8", { insertable: false, updatable: false }) },
        "view",
      ),
      noteView: tableMeta(
        "noteView",
        "note_view",
        { title: column("title", "text") },
        "view",
      ),
      files: tableMeta("files", "files", {
        paths: column("paths", "text", { array: true, storage: "docs" }),
      }),
    },
  },
  introspection: snapshotFixture.generator,
  extras: { tables: [], buckets: [], realtime: [] },
  config,
  output: resolve(root, config.output),
  importPath: (from, to) => importPath(resolve(root, from), resolve(root, to)),
  model: { tables: [], enums: [] },
};

const json = {
  "events.payload": "./src/schemas.ts#payloadSchema",
  "events.raw": "./src/schemas.ts#rawSchema",
  "other.data": "@acme/schemas#dataSchema",
};

const lines = (text: string) => text.split("\n");

describe("zod()", () => {
  it("writes a schema per variant with every scalar kind", async () => {
    const [file] = await zod({ json }).generate(input);
    expect(file!.path).toBe("src/generated.zod.ts");
    const text = lines(file!.contents);
    expect(text).toContain(
      'import type { InsertOf, RowOf, UpdateOf } from "./generated.ts";',
    );
    expect(text).toContain(
      'import { payloadSchema, rawSchema } from "./schemas.ts";',
    );
    expect(text).toContain('import { dataSchema } from "@acme/schemas";');
    expect(text).toContain(
      'import { isInstant, isPlainDateTime } from "better-supabase";',
    );
    expect(text).toEqual(
      expect.arrayContaining([
        "export const eventsRow: z.ZodType<RowOf<'events'>> = z.object({",
        "  id: z.int(),",
        "  amount: z.number().nullable(),",
        "  big: z.bigint(),",
        "  exact: z.string(),",
        "  at: z.custom<Temporal.Instant>(isInstant),",
        "  local: z.custom<Temporal.PlainDateTime>(isPlainDateTime),",
        "  day: z.iso.date(),",
        "  flag: z.boolean(),",
        "  labels: z.array(z.string()),",
        "  payload: payloadSchema,",
        "  meta: z.custom<NonNullable<RowOf<'events'>['meta']>>((value) => value !== undefined),",
        "  rec: z.unknown(),",
        '  "odd-name": z.string(),',
        "  amount: z.number().nullable().exactOptional(),",
        "  flag: z.boolean().exactOptional(),",
        "  paths: z.array((z.string() as unknown as z.ZodType<NonNullable<RowOf<'files'>['paths']>[number]>)),",
        "export const eventViewRow: z.ZodType<RowOf<'eventView'>> = z.object({",
      ]),
    );

    const insert = text.slice(
      text.indexOf(
        "export const eventsInsert: z.ZodType<InsertOf<'events'>> = z.object({",
      ),
    );

    expect(insert.slice(0, insert.indexOf("});"))).not.toContain(
      "  id: z.int(),",
    );
    expect(
      text.some((line) => line.startsWith("export const eventViewInsert")),
    ).toBe(false);
    expect(file!.contents).toContain(
      "  events: { insert: eventsInsert, update: eventsUpdate },",
    );
    expect(file!.contents).not.toContain("eventView: { insert");
    expect(text).toContain(
      "export const noteViewInsert: z.ZodType<InsertOf<'noteView'>> = z.object({",
    );
  });

  it("honours a custom output path", async () => {
    const [file] = await zod({ output: "src/schemas/zod.ts" }).generate(input);
    expect(file!.path).toBe("src/schemas/zod.ts");
    expect(file!.contents).toContain('from "../generated.ts";');
  });

  it("writes the functional zod/mini API with flavor mini", async () => {
    const [file] = await zod({ json, flavor: "mini" }).generate(input);
    const text = lines(file!.contents);
    expect(text).toContain('import { z } from "zod/mini";');
    expect(text).toEqual(
      expect.arrayContaining([
        "export const eventsRow: z.ZodMiniType<RowOf<'events'>> = z.object({",
        "  amount: z.nullable(z.number()),",
        "  amount: z.exactOptional(z.nullable(z.number())),",
        "  labels: z.array(z.string()),",
        "  paths: z.array((z.string() as unknown as z.ZodMiniType<NonNullable<RowOf<'files'>['paths']>[number]>)),",
      ]),
    );
    expect(file!.contents).not.toContain(".nullable()");
    expect(file!.contents).not.toMatch(/\)\.meta\(/);
    expect(file!.contents).toContain(".check(z.meta({ title: ");
  });
});

describe("valibot()", () => {
  it("writes a schema per variant with every scalar kind", async () => {
    const [file] = await valibot({ json }).generate(input);
    expect(file!.path).toBe("src/generated.valibot.ts");
    const text = lines(file!.contents);
    expect(text).toContain(
      'import { payloadSchema, rawSchema } from "./schemas.ts";',
    );
    expect(text).toContain('import { dataSchema } from "@acme/schemas";');
    expect(text).toContain(
      'import { isInstant, isPlainDateTime } from "better-supabase";',
    );
    expect(text).toEqual(
      expect.arrayContaining([
        "  id: v.pipe(v.number(), v.integer()),",
        "  amount: v.nullable(v.number()),",
        "  big: v.bigint(),",
        "  exact: v.string(),",
        "  at: v.custom<Temporal.Instant>(isInstant),",
        "  local: v.custom<Temporal.PlainDateTime>(isPlainDateTime),",
        "  day: v.pipe(v.string(), v.isoDate()),",
        "  flag: v.boolean(),",
        "  labels: v.array(v.string()),",
        "  payload: payloadSchema,",
        "  meta: v.custom<NonNullable<RowOf<'events'>['meta']>>((value) => value !== undefined),",
        "  rec: v.unknown(),",
        '  "odd-name": v.string(),',
        "  amount: v.exactOptional(v.nullable(v.number())),",
        "  paths: v.array((v.string() as unknown as v.GenericSchema<NonNullable<RowOf<'files'>['paths']>[number]>)),",
      ]),
    );
    expect(file!.contents).not.toContain("eventViewInsert");
  });

  it("honours a custom output path", async () => {
    const [file] = await valibot({ output: "lib/v.ts" }).generate(input);
    expect(file!.path).toBe("lib/v.ts");
  });
});

describe("jsonSchema()", () => {
  it("writes a property per scalar kind", async () => {
    const [file] = await jsonSchema({ id: "urn:test" }).generate(input);

    const doc = JSON.parse(file!.contents) as {
      $id: string;
      $defs: Record<string, { properties: Record<string, unknown> }>;
    };

    expect(doc.$id).toBe("urn:test");
    expect(doc.$defs["eventsRow"]?.properties).toMatchObject({
      id: { type: "integer" },
      amount: { type: ["number", "null"] },
      big: { type: "string", pattern: "^-?\\d+$" },
      exact: { type: "string" },
      at: { type: "string", format: "date-time" },
      local: { type: "string" },
      day: { type: "string", format: "date" },
      flag: { type: "boolean" },
      labels: { type: "array", items: { type: "string" } },
      payload: {},
      rec: {},
    });
  });
});

describe("standardSchema()", () => {
  it("writes a field spec per column with every scalar kind", async () => {
    const [file] = await standardSchema({ json }).generate(input);
    expect(file!.path).toBe("src/generated.standard.ts");
    const text = lines(file!.contents);
    expect(text).toContain(
      'import { type TableSchema, tableSchema } from "better-supabase";',
    );
    expect(text).toContain(
      'import { payloadSchema, rawSchema } from "./schemas.ts";',
    );
    expect(text).toContain('import { dataSchema } from "@acme/schemas";');
    expect(text).toEqual(
      expect.arrayContaining([
        "export const eventsRow: TableSchema<RowOf<'events'>> = tableSchema({",
        '    id: { kind: "integer" },',
        '    amount: { kind: "number", nullable: true },',
        '    big: { kind: "bigint" },',
        '    at: { kind: "instant" },',
        '    local: { kind: "plainDateTime" },',
        '    labels: { kind: "string", array: true },',
        '    payload: { kind: "json", schema: payloadSchema },',
        '    meta: { kind: "custom" },',
        '    rec: { kind: "unknown" },',
        '    "odd-name": { kind: "string" },',
        '    paths: { kind: "string", array: true },',
        "  events: { insert: eventsInsert, update: eventsUpdate },",
      ]),
    );
    expect(file!.contents).not.toContain("eventViewInsert");
  });

  it("matches buildJsonSchema for every variant", async () => {
    const [file] = await standardSchema().generate(input);
    const defs = buildJsonSchema(input)["$defs"] as Record<string, unknown>;

    for (const name of Object.keys(defs)) {
      expect(file!.contents).toContain(`export const ${name}: TableSchema<`);
    }
  });

  it("honours a custom output path", async () => {
    const [file] = await standardSchema({ output: "lib/s.ts" }).generate(input);
    expect(file!.path).toBe("lib/s.ts");
    expect(file!.contents).toContain('from "../src/generated.ts";');
  });
});
