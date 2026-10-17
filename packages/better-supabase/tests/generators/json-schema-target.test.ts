import { describe, expect, it } from "vitest";

import { toDraft07 } from "../../src/generators/json-schema-target.ts";

describe("toDraft07", () => {
  it("moves $defs to definitions and follows the $refs", () => {
    expect(
      toDraft07({
        $schema: "https://json-schema.org/draft/2020-12/schema",
        type: "object",
        properties: {
          tag: { $ref: "#/$defs/tag" },
          tags: { type: "array", items: { $ref: "#/$defs/tag" } },
          other: { $dynamicRef: "#/$defs/tag" },
        },
        $defs: { tag: { type: "string", $anchor: "tag" } },
      }),
    ).toEqual({
      type: "object",
      properties: {
        tag: { $ref: "#/definitions/tag" },
        tags: { type: "array", items: { $ref: "#/definitions/tag" } },
        other: { $ref: "#/definitions/tag" },
      },
      definitions: { tag: { type: "string" } },
    });
  });

  it("rewrites tuples and dependent keywords", () => {
    expect(
      toDraft07({
        type: "array",
        prefixItems: [{ type: "string" }, { type: "integer" }],
        items: false,
        unevaluatedItems: false,
      }),
    ).toEqual({
      type: "array",
      items: [{ type: "string" }, { type: "integer" }],
      additionalItems: false,
    });
    expect(
      toDraft07({
        type: "object",
        dependentRequired: { card: ["cvc"] },
        dependentSchemas: { vat: { required: ["country"] } },
        unevaluatedProperties: false,
      }),
    ).toEqual({
      type: "object",
      dependencies: { card: ["cvc"], vat: { required: ["country"] } },
    });
  });

  it("converts nested subschemas in every applicator", () => {
    const nested = { $ref: "#/$defs/x" };
    const lowered = { $ref: "#/definitions/x" };
    expect(
      toDraft07({
        anyOf: [nested, { type: "null" }],
        allOf: [nested],
        oneOf: [nested],
        not: nested,
        additionalProperties: nested,
        patternProperties: { "^a": nested },
        propertyNames: { type: "string" },
      }),
    ).toEqual({
      anyOf: [lowered, { type: "null" }],
      allOf: [lowered],
      oneOf: [lowered],
      not: lowered,
      additionalProperties: lowered,
      patternProperties: { "^a": lowered },
      propertyNames: { type: "string" },
    });
  });

  it("converts conditional subschemas", () => {
    const conditional = (schema: Record<string, unknown>) =>
      Object.fromEntries(["if", "then", "else"].map((key) => [key, schema]));

    expect(toDraft07(conditional({ $ref: "#/$defs/x" }))).toEqual(
      conditional({ $ref: "#/definitions/x" }),
    );
  });

  it("leaves a draft-07 schema as it is", () => {
    const schema = {
      type: "object",
      properties: { pair: { type: "array", items: [{ type: "string" }] } },
      definitions: { a: { type: "string" } },
      dependencies: { a: ["b"] },
      deprecated: true,
    };

    expect(toDraft07(schema)).toEqual(schema);
  });
});
