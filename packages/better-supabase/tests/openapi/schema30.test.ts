import { describe, expect, it } from "vitest";

import {
  lowerDocumentSchemas30,
  toOpenApi30Schema,
} from "../../src/openapi/schema30.ts";
import { deepFreeze } from "../spec/helpers.ts";

describe("toOpenApi30Schema", () => {
  it("turns null types into nullable", () => {
    expect(
      toOpenApi30Schema({ type: ["string", "null"], format: "uuid" }),
    ).toEqual({
      type: "string",
      format: "uuid",
      nullable: true,
    });
    expect(toOpenApi30Schema({ type: ["string", "integer"] })).toEqual({
      anyOf: [{ type: "string" }, { type: "integer" }],
    });
    expect(toOpenApi30Schema({ type: "null" })).toEqual({
      enum: [null],
      nullable: true,
    });
  });

  it("drops null branches and unwraps a single one", () => {
    expect(
      toOpenApi30Schema({
        anyOf: [{ $ref: "#/components/schemas/A" }, { type: "null" }],
      }),
    ).toEqual({ allOf: [{ $ref: "#/components/schemas/A" }], nullable: true });
    expect(
      toOpenApi30Schema({
        oneOf: [{ type: "string", minLength: 1 }, { type: "null" }],
        description: "d",
      }),
    ).toEqual({
      type: "string",
      minLength: 1,
      description: "d",
      nullable: true,
    });
    expect(
      toOpenApi30Schema({ allOf: [{ type: "null" }, { type: "string" }] }),
    ).toEqual({ allOf: [{ type: "string" }] });
  });

  it("rewrites 2020-12 keywords", () => {
    expect(
      toOpenApi30Schema({
        $schema: "https://json-schema.org/draft/2020-12/schema",
        $defs: {},
        type: "number",
        exclusiveMinimum: 0,
        exclusiveMaximum: 10,
        examples: [5, 6],
        prefixItems: [],
      }),
    ).toEqual({
      type: "number",
      minimum: 0,
      exclusiveMinimum: true,
      maximum: 10,
      exclusiveMaximum: true,
      example: 5,
    });
    expect(toOpenApi30Schema({ const: "a", examples: [] })).toEqual({
      enum: ["a"],
    });
    expect(
      toOpenApi30Schema({ type: "string", contentEncoding: "base64" }),
    ).toEqual({
      type: "string",
      format: "byte",
    });
    expect(
      toOpenApi30Schema({
        type: "string",
        contentEncoding: "base64",
        format: "x",
      }),
    ).toEqual({ type: "string", format: "x" });
  });

  it("wraps a $ref with siblings and recurses into subschemas", () => {
    expect(
      toOpenApi30Schema({ $ref: "#/components/schemas/A", description: "d" }),
    ).toEqual({
      allOf: [{ $ref: "#/components/schemas/A" }],
      description: "d",
    });
    expect(
      toOpenApi30Schema({
        type: "object",
        properties: { a: { type: ["integer", "null"] }, b: true },
        additionalProperties: { const: 1 },
        items: { type: ["string", "null"] },
        not: { const: 2 },
      }),
    ).toEqual({
      type: "object",
      properties: { a: { type: "integer", nullable: true }, b: true },
      additionalProperties: { enum: [1] },
      items: { type: "string", nullable: true },
      not: { enum: [2] },
    });
  });

  it("does not change its input", () => {
    const input = deepFreeze({ type: ["string", "null"], properties: {} });
    expect(() => toOpenApi30Schema(input)).not.toThrow();
  });
});

describe("lowerDocumentSchemas30", () => {
  it("lowers every schema position", () => {
    const nullable = { type: ["string", "null"] };
    const lowered = lowerDocumentSchemas30({
      paths: {
        "/a/{id}": {
          parameters: [{ name: "id", in: "path", schema: nullable }],
          "x-ext": { schema: nullable },
          get: {
            parameters: [{ name: "q", in: "query", schema: nullable }],
            requestBody: {
              content: { "application/json": { schema: nullable } },
            },
            responses: {
              "200": {
                headers: { h: { schema: nullable } },
                content: {
                  "text/event-stream": { "x-oai-itemSchema": nullable },
                },
              },
            },
          },
          post: { responses: {} },
        },
      },
      components: {
        schemas: { A: nullable },
        responses: {
          R: { content: { "application/json": { schema: nullable } } },
        },
        parameters: { P: { schema: nullable } },
      },
    });
    const expected = { type: "string", nullable: true };
    expect(lowered).toEqual({
      paths: {
        "/a/{id}": {
          parameters: [{ name: "id", in: "path", schema: expected }],
          "x-ext": { schema: nullable },
          get: {
            parameters: [{ name: "q", in: "query", schema: expected }],
            requestBody: {
              content: { "application/json": { schema: expected } },
            },
            responses: {
              "200": {
                headers: { h: { schema: expected } },
                content: {
                  "text/event-stream": { "x-oai-itemSchema": expected },
                },
              },
            },
          },
          post: { responses: {} },
        },
      },
      components: {
        schemas: { A: expected },
        responses: {
          R: { content: { "application/json": { schema: expected } } },
        },
        parameters: { P: { schema: expected } },
      },
    });
    expect(lowerDocumentSchemas30({ components: {} })).toEqual({
      components: {},
    });
  });
});
