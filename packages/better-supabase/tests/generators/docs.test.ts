import { toJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  parseCheckBounds,
  parseComment,
  titleOf,
} from "../../src/generators/shared.ts";
import jsonSchema from "../fixtures/generated-camel.schema.json" with { type: "json" };
import * as valibotSchemas from "../fixtures/generated-camel.valibot.ts";
import * as zodSchemas from "../fixtures/generated-camel.zod.ts";

describe("parseComment", () => {
  it("splits the description from @example lines", () => {
    expect(
      parseComment('Trading name.\n@example "Acme B.V."\n@example 42'),
    ).toEqual({ description: "Trading name.", examples: ["Acme B.V.", 42] });
  });

  it("keeps an example that is not JSON as text", () => {
    expect(parseComment("@example Acme B.V.")).toEqual({
      examples: ["Acme B.V."],
    });
  });

  it("reads nothing from a missing comment", () => {
    expect(parseComment(null)).toEqual({ examples: [] });
  });
});

describe("parseCheckBounds", () => {
  const bounds = (definition: string) =>
    Object.fromEntries(parseCheckBounds(definition));

  it("reads value bounds, casts and between", () => {
    expect(bounds("CHECK ((price >= (0)::numeric))")).toEqual({
      price: { minimum: 0 },
    });
    expect(bounds("CHECK (((rating >= 1) AND (rating <= 5)))")).toEqual({
      rating: { minimum: 1, maximum: 5 },
    });
    expect(bounds("max_requests > 0")).toEqual({
      max_requests: { exclusiveMinimum: 0 },
    });
    expect(bounds('CHECK (("weight" < 2.5))')).toEqual({
      weight: { exclusiveMaximum: 2.5 },
    });
  });

  it("reads length bounds from length and char_length", () => {
    expect(
      bounds(
        "CHECK (((char_length(name) >= 1) AND (char_length(name) <= 200)))",
      ),
    ).toEqual({ name: { minLength: 1, maxLength: 200 } });
    expect(
      bounds("CHECK (((length(code) > 2) AND (length(code) < 10)))"),
    ).toEqual({ code: { minLength: 3, maxLength: 9 } });
  });

  it("flips a constant on the left", () => {
    expect(bounds("CHECK ((0 < quantity))")).toEqual({
      quantity: { exclusiveMinimum: 0 },
    });
    expect(bounds("CHECK ((200 >= char_length(name)))")).toEqual({
      name: { maxLength: 200 },
    });
  });

  it("leaves out OR chains, other functions and column comparisons", () => {
    expect(bounds("CHECK (((a > 0) OR (b > 0)))")).toEqual({});
    expect(bounds("CHECK ((char_length(TRIM(BOTH FROM name)) > 0))")).toEqual(
      {},
    );
    expect(bounds("CHECK ((ends_at > starts_at))")).toEqual({});
    expect(bounds("CHECK (((status = 'a'::text) AND (amount >= 0)))")).toEqual({
      amount: { minimum: 0 },
    });
  });
});

describe("titleOf", () => {
  it("turns a table name into a title", () => {
    expect(titleOf("customer_tags")).toBe("Customer tags");
  });
});

describe("generated docs", () => {
  const customersInsert = jsonSchema.$defs.customersInsert;

  it("writes title, description, examples and bounds to JSON Schema", () => {
    expect(customersInsert.title).toBe("Customers insert");
    expect(customersInsert.description).toBe(
      "Companies the organization sells to.",
    );
    expect(customersInsert.properties.name).toEqual({
      type: "string",
      minLength: 1,
      maxLength: 200,
      description: "Trading name.",
      examples: ["Acme B.V."],
    });
  });

  it("enforces the bounds in the validators", () => {
    const customer = {
      organizationId: "00000000-0000-4000-8000-000000000001",
      name: "",
    };
    expect(zodSchemas.customersInsert.safeParse(customer).success).toBe(false);
    expect(v.safeParse(valibotSchemas.customersInsert, customer).success).toBe(
      false,
    );
    const long = { ...customer, name: "x".repeat(201) };
    expect(zodSchemas.customersInsert.safeParse(long).success).toBe(false);
  });

  it("carries the same docs into each library's JSON Schema", () => {
    const fromZod = (
      zodSchemas.customersInsert["~standard"] as unknown as {
        jsonSchema: {
          input(options: {
            target: string;
            libraryOptions: Record<string, unknown>;
          }): unknown;
        };
      }
    ).jsonSchema.input({
      target: "draft-2020-12",
      libraryOptions: { unrepresentable: "any" },
    });
    const fromValibot = toJsonSchema(valibotSchemas.customersInsert, {
      errorMode: "ignore",
    });
    for (const converted of [fromZod, fromValibot]) {
      expect(converted).toMatchObject({
        title: "Customers insert",
        description: "Companies the organization sells to.",
        properties: {
          name: {
            minLength: 1,
            maxLength: 200,
            description: "Trading name.",
            examples: ["Acme B.V."],
          },
        },
      });
    }
  });
});
