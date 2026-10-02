import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { defineListQuery } from "../../src/list/index.ts";
import { createOpenApi } from "../../src/openapi/index.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { metaSchema2020, problems, validatorFor } from "./validator.ts";

const sb = defineSupabase(schema);
const customers = defineListQuery(sb, "customers", {
  search: ["name"],
  facets: { status: "status" },
  sorts: { name: { name: "asc" } },
  defaultSort: "name",
});

const doc = createOpenApi(sb, {
  info: { title: "CRM", version: "1.0.0", description: "Customers" },
  servers: [{ url: "https://api.test" }],
  basePath: "/api",
  resources: {
    customers: { list: customers },
    notes: { operations: ["list", "get"] },
    tags: true,
  },
  security: ["bearer", "oauth2"],
  supabaseUrl: "https://abc.supabase.co",
});

function schemasIn(value: unknown, out: unknown[] = []): unknown[] {
  if (Array.isArray(value)) for (const item of value) schemasIn(item, out);
  else if (value && typeof value === "object") {
    for (const [key, item] of Object.entries(value)) {
      if (key === "schema") out.push(item);
      else schemasIn(item, out);
    }
  }
  return out;
}

describe("OpenAPI 3.1", () => {
  it("emits the pinned version (SPEC_PINS.openapi)", () => {
    expect(doc.openapi).toBe(SPEC_PINS.openapi);
    expect(doc.openapi).toMatch(/^3\.1\.\d+$/);
  });

  it("validates against the official OpenAPI 3.1 schema", () => {
    const validate = validatorFor("openapi-3.1.json");
    expect(problems(validate, JSON.parse(JSON.stringify(doc)))).toEqual([]);
  });

  it("declares the 2020-12 dialect (OAS 3.1 section 4.8.1 jsonSchemaDialect)", () => {
    expect(doc.jsonSchemaDialect).toBe(
      "https://json-schema.org/draft/2020-12/schema",
    );
  });

  it("every component and inline schema is a valid JSON Schema 2020-12 schema", () => {
    const meta = metaSchema2020();
    for (const [name, component] of Object.entries(doc.components.schemas))
      expect([name, problems(meta, component)]).toEqual([name, []]);
    for (const inline of schemasIn(doc.paths))
      expect(problems(meta, inline)).toEqual([]);
  });

  it("resolves every $ref inside the document", () => {
    const text = JSON.stringify(doc);
    for (const [, target] of text.matchAll(/"\$ref":"#\/([^"]+)"/g)) {
      const node = target!
        .split("/")
        .reduce<unknown>(
          (current, key) =>
            (current as Record<string, unknown> | undefined)?.[key],
          doc,
        );
      expect(node).toBeDefined();
    }
  });

  it("is rejected by the official schema when a required field is missing", () => {
    const validate = validatorFor("openapi-3.1.json");
    const { info: _info, ...broken } = JSON.parse(
      JSON.stringify(doc),
    ) as Record<string, unknown>;
    expect(problems(validate, broken)).not.toEqual([]);
  });
});
