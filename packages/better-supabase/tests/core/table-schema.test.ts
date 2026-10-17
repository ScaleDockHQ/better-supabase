import type {
  StandardJSONSchemaV1,
  StandardSchemaV1,
} from "@standard-schema/spec";

import { describe, expect, it } from "vitest";

import {
  type FieldSpec,
  tableSchema,
  type TableSchemaSpec,
} from "../../src/core/table-schema.ts";

type Row = Record<string, unknown>;

function check(
  spec: TableSchemaSpec,
  value: unknown,
): StandardSchemaV1.Result<Row> {
  const result = tableSchema<Row>(spec)["~standard"].validate(value);
  if (result instanceof Promise) {
    throw new TypeError("expected a sync result");
  }
  return result;
}

const one = (field: FieldSpec, value: unknown) =>
  check({ fields: { v: field } }, { v: value });

const messages = (result: StandardSchemaV1.Result<Row>) =>
  result.issues?.map((issue) => issue.message) ?? [];

describe("tableSchema() validation", () => {
  it.each<[FieldSpec, unknown, unknown]>([
    [{ kind: "uuid" }, "00000000-0000-4000-8000-000000000001", "nope"],
    [{ kind: "string" }, "a", 1],
    [{ kind: "integer" }, 3, 3.5],
    [{ kind: "number" }, 3.5, Number.NaN],
    [{ kind: "boolean" }, false, "false"],
    [{ kind: "datetime" }, "2026-09-24T09:35:10.123456+00:00", "2026-09-24"],
    [{ kind: "date" }, "2026-09-24", "24-09-2026"],
    [{ kind: "instant" }, Temporal.Instant.fromEpochMilliseconds(0), "x"],
    [
      { kind: "plainDateTime" },
      Temporal.PlainDateTime.from("2026-01-01T00:00"),
      "x",
    ],
    [{ kind: "bigint" }, 1n, 1],
    [{ kind: "json" }, { a: [1, "b", null, { c: true }] }, { a: () => 1 }],
    [{ kind: "enum", values: ["a", "b"] }, "a", "c"],
    [{ kind: "custom" }, { any: "thing" }, undefined],
  ])("%o accepts its type and rejects others", (field, good, bad) => {
    expect(one(field, good)).toEqual({ value: { v: good } });
    expect(messages(one(field, bad))).toHaveLength(1);
  });

  it("rejects JSON values JSON can't hold", () => {
    expect(messages(one({ kind: "json" }, Number.POSITIVE_INFINITY))).toEqual([
      "Expected a JSON value",
    ]);
    expect(messages(one({ kind: "json" }, new Date()))).toEqual([
      "Expected a JSON value",
    ]);
    expect(one({ kind: "json" }, Object.create(null))).toHaveProperty("value");
  });

  it("checks value and length bounds", () => {
    const number: FieldSpec = {
      kind: "number",
      minimum: 0,
      exclusiveMaximum: 10,
    };
    expect(messages(one(number, -1))).toEqual(["Expected at least 0"]);
    expect(messages(one(number, 10))).toEqual(["Expected less than 10"]);
    expect(
      messages(one({ kind: "integer", exclusiveMinimum: 0, maximum: 5 }, 0)),
    ).toEqual(["Expected more than 0"]);
    expect(messages(one({ kind: "integer", maximum: 5 }, 6))).toEqual([
      "Expected at most 5",
    ]);
    const text: FieldSpec = { kind: "string", minLength: 2, maxLength: 3 };
    expect(messages(one(text, "a"))).toEqual([
      "Expected at least 2 characters",
    ]);
    expect(messages(one(text, "abcd"))).toEqual([
      "Expected at most 3 characters",
    ]);
  });

  it("reports array elements by index and accepts null when nullable", () => {
    const field: FieldSpec = { kind: "string", array: true, nullable: true };
    expect(one(field, null)).toEqual({ value: { v: null } });
    expect(one(field, "a").issues).toEqual([
      { message: "Expected an array", path: ["v"] },
    ]);
    expect(one(field, ["a", 1]).issues).toEqual([
      { message: "Expected a string", path: ["v", 1] },
    ]);
    expect(messages(one({ kind: "string" }, null))).toEqual([
      "Expected a string",
    ]);
  });

  it("requires keys unless optional or unknown, and drops unknown keys", () => {
    const spec: TableSchemaSpec = {
      fields: {
        a: { kind: "string" },
        b: { kind: "string", optional: true },
        c: { kind: "unknown" },
      },
    };
    expect(check(spec, { a: "x", extra: 1 })).toEqual({ value: { a: "x" } });
    expect(check(spec, {}).issues).toEqual([
      { message: "Required", path: ["a"] },
    ]);
    expect(messages(check(spec, { a: "x", b: undefined }))).toEqual([
      "Expected a string",
    ]);
    expect(check(spec, [])).toEqual({
      issues: [{ message: "Expected an object" }],
    });
    expect(check(spec, null)).toEqual({
      issues: [{ message: "Expected an object" }],
    });
  });

  it("delegates to a nested schema, sync or async, with nested paths", async () => {
    const nested = (async: boolean): StandardSchemaV1 => ({
      "~standard": {
        version: 1,
        vendor: "test",
        validate: (value) => {
          const result: StandardSchemaV1.Result<unknown> =
            typeof value === "object"
              ? { value }
              : { issues: [{ message: "Nope", path: ["tier"] }] };
          return async ? Promise.resolve(result) : result;
        },
      },
    });
    expect(one({ kind: "json", schema: nested(false) }, 1).issues).toEqual([
      { message: "Nope", path: ["v", "tier"] },
    ]);
    expect(
      one({ kind: "json", schema: nested(false), array: true }, [{}]),
    ).toEqual({ value: { v: [{}] } });
    const schema = tableSchema<Row>({
      fields: {
        v: { kind: "json", schema: nested(true) },
        w: { kind: "string" },
      },
    });
    await expect(schema["~standard"].validate({ v: 1, w: 2 })).resolves.toEqual(
      {
        issues: [
          { message: "Expected a string", path: ["w"] },
          { message: "Nope", path: ["v", "tier"] },
        ],
      },
    );
    await expect(
      schema["~standard"].validate({ v: {}, w: "x" }),
    ).resolves.toEqual({ value: { v: {}, w: "x" } });
  });
});

describe("tableSchema() JSON Schema", () => {
  const spec: TableSchemaSpec = {
    title: "Customers",
    description: "People who buy.",
    fields: {
      id: { kind: "uuid", readOnly: true },
      status: {
        kind: "enum",
        values: ["lead", "active"],
        nullable: true,
        optional: true,
      },
      rating: {
        kind: "integer",
        exclusiveMinimum: 0,
        exclusiveMaximum: 6,
        nullable: true,
        examples: [4],
      },
      tags: { kind: "string", array: true, nullable: true },
      meta: { kind: "json", nullable: true, description: "Free form." },
    },
  };
  const json = tableSchema(spec)["~standard"].jsonSchema;

  it("writes draft 2020-12 and draft-07 with their $schema", () => {
    const schema = json.input({ target: "draft-2020-12" });
    expect(schema).toEqual({
      $schema: "https://json-schema.org/draft/2020-12/schema",
      title: "Customers",
      description: "People who buy.",
      type: "object",
      properties: {
        id: { type: "string", format: "uuid", readOnly: true },
        status: { type: ["string", "null"], enum: ["lead", "active", null] },
        rating: {
          type: ["integer", "null"],
          exclusiveMinimum: 0,
          exclusiveMaximum: 6,
          examples: [4],
        },
        tags: { type: ["array", "null"], items: { type: "string" } },
        meta: { description: "Free form." },
      },
      required: ["id", "rating", "tags", "meta"],
      additionalProperties: false,
    });
    expect(json.output({ target: "draft-07" })["$schema"]).toBe(
      "http://json-schema.org/draft-07/schema#",
    );
  });

  it("rewrites nullability, examples and exclusive bounds for OpenAPI 3.0", () => {
    const schema = json.input({ target: "openapi-3.0" });
    expect(schema).not.toHaveProperty("$schema");
    expect(schema["properties"]).toEqual({
      id: { type: "string", format: "uuid", readOnly: true },
      status: {
        type: "string",
        enum: ["lead", "active", null],
        nullable: true,
      },
      rating: {
        type: "integer",
        minimum: 0,
        exclusiveMinimum: true,
        maximum: 6,
        exclusiveMaximum: true,
        example: 4,
        nullable: true,
      },
      tags: { type: "array", items: { type: "string" }, nullable: true },
      meta: { description: "Free form." },
    });
  });

  it("throws for a target it doesn't support", () => {
    expect(() => json.input({ target: "draft-04" })).toThrow(
      'Unsupported JSON Schema target "draft-04"',
    );
  });

  it("uses a nested schema's own JSON Schema when it has one", () => {
    const targets: string[] = [];
    const nested: StandardSchemaV1 = {
      "~standard": {
        version: 1,
        vendor: "test",
        validate: (value) => ({ value }),
        jsonSchema: {
          input: (options: StandardJSONSchemaV1.Options) => {
            targets.push(options.target);
            return { $schema: "x", type: "object" };
          },
          output: () => ({ type: "string" }),
        },
      } as StandardSchemaV1.Props,
    };
    const schema = tableSchema({
      fields: { meta: { kind: "json", schema: nested, nullable: true } },
    })["~standard"].jsonSchema;
    expect(schema.input({ target: "draft-07" })["properties"]).toEqual({
      meta: { type: ["object", "null"] },
    });
    expect(schema.output({ target: "draft-07" })["properties"]).toEqual({
      meta: { type: ["string", "null"] },
    });
    expect(targets).toEqual(["draft-07"]);
    const oneOf: StandardSchemaV1 = {
      "~standard": {
        version: 1,
        vendor: "test",
        validate: (value) => ({ value }),
        jsonSchema: {
          input: () => ({ oneOf: [{ type: "string" }, { type: "number" }] }),
          output: () => ({}),
        },
      } as StandardSchemaV1.Props,
    };
    const either = tableSchema({
      fields: { v: { kind: "json", schema: oneOf, nullable: true } },
    })["~standard"].jsonSchema;
    expect(either.input({ target: "draft-07" })["properties"]).toEqual({
      v: {
        anyOf: [
          { oneOf: [{ type: "string" }, { type: "number" }] },
          { type: "null" },
        ],
      },
    });
    expect(either.input({ target: "openapi-3.0" })["properties"]).toEqual({
      v: { oneOf: [{ type: "string" }, { type: "number" }], nullable: true },
    });
    const plain = tableSchema({
      fields: {
        meta: {
          kind: "json",
          schema: {
            "~standard": {
              version: 1,
              vendor: "v",
              validate: (value) => ({ value }),
            },
          },
        },
      },
    })["~standard"].jsonSchema;
    expect(plain.input({ target: "draft-07" })["properties"]).toEqual({
      meta: {},
    });
  });
});
