import { describe, expect, expectTypeOf, it } from "vitest";

import type { StandardSchemaV1 } from "../../src/core/standard.ts";

import { generatedOptions } from "../../src/blocks/block-config.ts";
import { columnsSchema } from "../../src/core/columns-schema.ts";

const schema = columnsSchema({
  region: "text not null",
  seats: "int4",
  budget: "numeric(12, 2)",
  flags: "text[]",
});

function check(value: unknown) {
  const outcome = schema["~standard"].validate(value);

  if (outcome instanceof Promise) {
    throw new TypeError("expected a synchronous schema");
  }

  return outcome;
}

describe("columnsSchema", () => {
  it("accepts a row that matches the column types", () => {
    expect(
      check({ region: "us", seats: 3, budget: "10.50", flags: ["a"] }),
    ).toEqual({
      value: { region: "us", seats: 3, budget: "10.50", flags: ["a"] },
    });
  });

  it("makes a not null column required and the others optional", () => {
    expect(check({})).toMatchObject({
      issues: [{ message: "region is required", path: ["region"] }],
    });

    expect(check({ region: "us", seats: null })).toHaveProperty("value");
  });

  it("holds numeric and int8 values as strings", () => {
    expect(check({ region: "us", budget: 10 })).toMatchObject({
      issues: [{ path: ["budget"] }],
    });
  });

  it("checks each element of an array column", () => {
    expect(check({ region: "us", flags: ["a", 1] })).toMatchObject({
      issues: [{ path: ["flags"] }],
    });
  });

  it("passes keys it doesn't list", () => {
    expect(check({ region: "us", other: 1 })).toHaveProperty("value.other", 1);
  });
});

describe("generatedOptions", () => {
  it("adds fields from the entry's columns", () => {
    const options = generatedOptions({
      schema: "better_supabase",
      options: {},
      columns: { region: "text not null" },
    } as const);

    expect(options.schema).toBe("better_supabase");
    expect(options.fields["~standard"].vendor).toBe("better-supabase");
  });

  it("adds none without columns", () => {
    expect(generatedOptions({ schema: "s", options: {} })).not.toHaveProperty(
      "fields",
    );
  });
});

describe("columnsSchema required columns", () => {
  const required = columnsSchema({ name: "text not null", seats: "int4" });

  const issues = (value: unknown): readonly string[] => {
    const outcome = required["~standard"].validate(value);

    if (outcome instanceof Promise) {
      throw new TypeError("expected a synchronous schema");
    }

    return (outcome.issues ?? []).map((issue) => issue.message);
  };

  it("reports a missing and a null required column", () => {
    expect(issues({})).toEqual(["name is required"]);
    expect(issues({ name: null })).toEqual(["name can't be null"]);
  });

  it("lets an optional column be missing or null", () => {
    expect(issues({ name: "a", seats: null })).toEqual([]);
    expect(issues({ name: "a" })).toEqual([]);
  });
});

describe("columnsSchema defaults", () => {
  const defaults = columnsSchema({
    name: "text not null",
    risk: "text not null default 'low'",
    metadata: "jsonb not null default '{}'::jsonb",
  });

  const issues = (value: unknown): readonly string[] => {
    const outcome = defaults["~standard"].validate(value);

    if (outcome instanceof Promise) {
      throw new TypeError("expected a synchronous schema");
    }

    return (outcome.issues ?? []).map((issue) => issue.message);
  };

  it("lets a not null column with a default be missing on input", () => {
    expect(issues({ name: "a" })).toEqual([]);
  });

  it("still checks a default column's value and rejects null", () => {
    expect(issues({ name: "a", risk: "high" })).toEqual([]);
    expect(issues({ name: "a", risk: 3 })).toHaveLength(1);
    expect(issues({ name: "a", risk: null })).toEqual(["risk can't be null"]);
  });

  it("still requires a not null column without a default", () => {
    expect(issues({})).toEqual(["name is required"]);
  });

  it("types the default column optional on input and required on output", () => {
    type Input = StandardSchemaV1.InferInput<typeof defaults>;

    type Output = StandardSchemaV1.InferOutput<typeof defaults>;

    expectTypeOf<Input>().toHaveProperty("name");
    expectTypeOf<{ name: string }>().toExtend<Input>();
    expectTypeOf<Output["risk"]>().toEqualTypeOf<string>();
    expectTypeOf<Output["metadata"]>().toEqualTypeOf<unknown>();
  });
});

describe("columnsSchema types", () => {
  const typed = columnsSchema({ active: "boolean", meta: "jsonb" });

  const issues = (value: unknown): readonly string[] => {
    const outcome = typed["~standard"].validate(value);

    if (outcome instanceof Promise) {
      throw new TypeError("expected a synchronous schema");
    }

    return (outcome.issues ?? []).map((issue) => issue.message);
  };

  it("checks booleans and accepts any value for other types", () => {
    expect(issues({ active: true, meta: { a: 1 } })).toEqual([]);
    expect(issues({ active: "yes" })).toHaveLength(1);
  });

  it("rejects a value that is not an object", () => {
    expect(issues("row")).toEqual(["Expected an object"]);
  });
});
