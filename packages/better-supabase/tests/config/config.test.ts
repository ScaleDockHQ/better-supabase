import { toStandardJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { resolveJsonSchema } from "../../src/config/index.ts";

describe("resolveJsonSchema", () => {
  const tuple = toStandardJsonSchema(v.tuple([v.string()]));

  it("converts a Standard Schema for 2020-12 by default", () => {
    expect(resolveJsonSchema(tuple)).toMatchObject({
      $schema: "https://json-schema.org/draft/2020-12/schema",
      prefixItems: [{ type: "string" }],
    });
  });

  it("converts for another target", () => {
    expect(resolveJsonSchema(tuple, "draft-07")).toMatchObject({
      $schema: "http://json-schema.org/draft-07/schema#",
      items: [{ type: "string" }],
    });
  });

  it("returns a JSON Schema object as it is", () => {
    expect(resolveJsonSchema({ type: "array" }, "draft-07")).toEqual({
      type: "array",
    });
  });
});
