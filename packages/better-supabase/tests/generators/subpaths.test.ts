import { describe, expect, it } from "vitest";

import * as config from "../../src/config/index.ts";
import * as factories from "../../src/generators/factories/index.ts";
import * as jsonSchema from "../../src/generators/json-schema/index.ts";
import * as nuqs from "../../src/generators/nuqs/index.ts";
import * as standardSchema from "../../src/generators/standard-schema/index.ts";
import * as valibot from "../../src/generators/valibot/index.ts";
import * as zod from "../../src/generators/zod/index.ts";

describe("better-supabase/generators/*", () => {
  it.each([
    ["zod", zod.zod],
    ["valibot", valibot.valibot],
    ["json-schema", jsonSchema.jsonSchema],
    ["standard-schema", standardSchema.standardSchema],
    ["factories", factories.factories],
    ["nuqs", nuqs.nuqs],
  ])("%s is a generator at apiVersion 2", (name, make) => {
    expect(make().name).toBe(name);
    expect(make().apiVersion).toBe(2);
  });

  it("better-supabase/config no longer exports the generators", () => {
    for (const name of [
      "zod",
      "valibot",
      "jsonSchema",
      "standardSchema",
      "factories",
      "nuqs",
      "toJsonSchema",
    ]) {
      expect(config).not.toHaveProperty(name);
    }
  });

  it("exports toJsonSchema next to jsonSchema", () => {
    expect(typeof jsonSchema.toJsonSchema).toBe("function");
  });
});
