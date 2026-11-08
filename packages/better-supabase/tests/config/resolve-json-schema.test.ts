import { describe, expect, it } from "vitest";

import { resolveJsonSchema } from "../../src/config/json.ts";

describe("resolveJsonSchema", () => {
  it("returns a JSON Schema object as it is", () => {
    const schema = { type: "string" };
    expect(resolveJsonSchema(schema)).toBe(schema);
  });

  it("converts a Standard JSON Schema for the target", () => {
    const source = {
      "~standard": {
        jsonSchema: { input: ({ target }: { target: string }) => ({ target }) },
      },
    };

    // SAFETY: the stub carries only the part of Standard Schema this reads.
    expect(resolveJsonSchema(source as never, "draft-07")).toEqual({
      target: "draft-07",
    });
  });

  it("refuses a Standard Schema without Standard JSON Schema", () => {
    const source = { "~standard": { version: 1 } };

    // SAFETY: the stub carries only the part of Standard Schema this reads.
    expect(() => resolveJsonSchema(source as never)).toThrow(
      /does not implement Standard JSON Schema/u,
    );
  });
});
