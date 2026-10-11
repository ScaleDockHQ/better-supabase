import { toStandardJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { resolveConfig, resolveJsonSchema } from "../../src/config/index.ts";

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

describe("resolveConfig specs", () => {
  it("defaults to one OpenAPI output", () => {
    expect(resolveConfig({}, "/app").specs).toEqual({
      entry: "src/lib/openapi.ts",
      outputs: [{ format: "openapi", output: "openapi.json" }],
      failOn: "error",
    });
  });

  it("reads the deprecated openapi key as an alias", () => {
    expect(
      resolveConfig(
        // oxlint-disable-next-line typescript/no-deprecated -- the alias under test
        { openapi: { entry: "api.ts", output: "docs/openapi.json" } },
        "/app",
      ).specs,
    ).toEqual({
      entry: "api.ts",
      outputs: [{ format: "openapi", output: "docs/openapi.json" }],
      failOn: "error",
    });
  });

  it("prefers specs over openapi", () => {
    const outputs = [{ format: "asyncapi" }] as const;
    expect(
      resolveConfig(
        {
          // oxlint-disable-next-line typescript/no-deprecated -- the alias under test
          openapi: { entry: "old.ts" },
          specs: { entry: "new.ts", outputs, failOn: "warning" },
        },
        "/app",
      ).specs,
    ).toEqual({ entry: "new.ts", outputs, failOn: "warning" });
  });
});
