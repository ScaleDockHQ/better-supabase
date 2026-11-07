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
  ])(
    "%s is the generator better-supabase/config also exports",
    (name, make) => {
      expect(make().name).toBe(name);
      expect(Object.values(config)).toContain(make);
    },
  );

  it("exports toJsonSchema next to jsonSchema", () => {
    expect(jsonSchema.toJsonSchema).toBe(config.toJsonSchema);
  });
});
