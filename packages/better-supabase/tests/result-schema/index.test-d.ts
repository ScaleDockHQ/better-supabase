import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expectTypeOf, it } from "vitest";

import type { ReadSetResult } from "../../src/core/read-set.ts";
import type { resultSchema } from "../../src/result-schema/index.ts";

import { createSupabase } from "../../src/core/define.ts";
import { defineReadSet } from "../../src/core/read-set.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = createSupabase(schema);

const chrome = defineReadSet(betterSupabase, "result_types", {}, (s) => ({
  names: s.customers.list({ select: ["id", "name"] }),
  total: s.customers.count(),
}));

describe("resultSchema types", () => {
  it("matches ReadSetResult", () => {
    expectTypeOf<
      StandardSchemaV1.InferOutput<
        ReturnType<typeof resultSchema<typeof chrome>>
      >
    >().toEqualTypeOf<ReadSetResult<typeof chrome>>();
  });
});
