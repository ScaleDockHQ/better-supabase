import { describe, expect, it } from "vitest";

import { generatedOptions } from "../../src/blocks/block-config.ts";
import { columnsSchema } from "../../src/core/columns-schema.ts";

const schema = columnsSchema({
  region: "text not null default 'eu'",
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
