import { readFile } from "node:fs/promises";
import { dirname, relative, resolve, sep } from "node:path";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { GeneratorInput } from "../../src/config/index.ts";
import type { ColumnMeta, TableMeta } from "../../src/schema/types.ts";

import { resolveConfig } from "../../src/config/index.ts";
import { valibot } from "../../src/generators/valibot.ts";
import { zod } from "../../src/generators/zod.ts";
import * as valibotSchemas from "../fixtures/generated-camel.valibot.ts";
import * as zodSchemas from "../fixtures/generated-camel.zod.ts";
import fixture from "../fixtures/snapshot.json" with { type: "json" };

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
      result.error?.issues.map((issue) => issue.path.join(".")).sort(),
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

describe("json schema generator", () => {
  it("writes $defs with required columns and nullable types", async () => {
    const doc = JSON.parse(
      await readFile(
        new URL("../fixtures/generated-camel.schema.json", import.meta.url),
        "utf8",
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
        { id: column("id", "int8") },
        "view",
      ),
      files: tableMeta("files", "files", {
        paths: column("paths", "text", { array: true, storage: "docs" }),
      }),
    },
  },
  introspection: fixture.generator as GeneratorInput["introspection"],
  extras: { tables: [], buckets: [], realtime: [] },
  config,
  output: resolve(root, config.output),
  importPath: (from, to) => importPath(resolve(root, from), resolve(root, to)),
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
  });

  it("honours a custom output path", async () => {
    const [file] = await zod({ output: "src/schemas/zod.ts" }).generate(input);
    expect(file!.path).toBe("src/schemas/zod.ts");
    expect(file!.contents).toContain('from "../generated.ts";');
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
