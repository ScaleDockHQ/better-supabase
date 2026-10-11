import { describe, expect, it } from "vitest";

import type { ColumnMeta, TableMeta } from "../../src/schema/types.ts";

import {
  buildJsonSchema,
  jsonSchema,
} from "../../src/generators/json-schema.ts";

const column = (
  db: string,
  type: string,
  extra: Partial<ColumnMeta> = {},
): ColumnMeta => ({ db, type, nullable: false, hasDefault: false, ...extra });

const accounts: TableMeta = {
  key: "accounts",
  name: "accounts",
  schema: "public",
  kind: "table",
  columns: {
    id: column("id", "uuid", { hasDefault: true }),
    name: column("name", "text", { description: "Display name." }),
    legacyCode: column("legacy_code", "text", {
      nullable: true,
      deprecated: true,
      description: "The old code.",
    }),
    score: column("score", "numeric", { nullable: true }),
  },
  primaryKey: ["id"],
  uniqueKeys: {},
  relations: {},
  flags: {},
  description: "Customer accounts.",
  deprecated: true,
};

const input = {
  meta: {
    version: 1 as const,
    casing: "camel" as const,
    enums: {},
    functions: {},
    tables: { accounts },
  },
  config: { json: {} },
};

type Doc = Record<string, Record<string, Record<string, unknown>>>;

describe("buildJsonSchema", () => {
  it("reads descriptions and deprecated from the meta without a catalog", () => {
    const doc = buildJsonSchema(input) as Doc;
    const row = doc["$defs"]!["accountsRow"]!;
    expect(row["description"]).toBe("Customer accounts.");
    expect(row["deprecated"]).toBe(true);
    expect(row["properties"]).toMatchObject({
      name: { type: "string", description: "Display name." },
      legacyCode: {
        type: ["string", "null"],
        description: "The old code.",
        deprecated: true,
      },
    });
    expect(row["properties"]).toHaveProperty("id", {
      type: "string",
      format: "uuid",
    });
  });

  it("writes a draft-07 document under definitions", () => {
    const doc = buildJsonSchema(
      input,
      "https://acme.test/schema.json",
      "draft-07",
    );
    expect(doc["$schema"]).toBe("http://json-schema.org/draft-07/schema#");
    expect(doc["$id"]).toBe("https://acme.test/schema.json");
    expect(doc).not.toHaveProperty("$defs");
    expect(Object.keys(doc["definitions"] as object)).toEqual([
      "accountsRow",
      "accountsInsert",
      "accountsUpdate",
    ]);
  });

  it("writes the OpenAPI 3.0 dialect with nullable", () => {
    const doc = buildJsonSchema(input, undefined, "openapi-3.0") as Doc;
    expect(doc).not.toHaveProperty("$schema");
    expect(doc["definitions"]!["accountsRow"]!["properties"]).toMatchObject({
      legacyCode: { type: "string", nullable: true, deprecated: true },
      score: { type: "number", nullable: true },
    });
  });

  it("keeps the default 2020-12 document", () => {
    const doc = buildJsonSchema(input);
    expect(doc["$schema"]).toBe("https://json-schema.org/draft/2020-12/schema");
    expect(doc).toHaveProperty("$defs");
  });
});

describe("jsonSchema()", () => {
  it("passes the target to the written document", async () => {
    const [file] = await jsonSchema({ target: "draft-07" }).generate({
      ...input,
      config: { ...input.config, output: "src/generated.ts" },
    } as never);
    expect(file!.path).toBe("src/generated.schema.json");
    expect(JSON.parse(file!.contents)).toMatchObject({
      $schema: "http://json-schema.org/draft-07/schema#",
      definitions: { accountsRow: { deprecated: true } },
    });
  });
});
