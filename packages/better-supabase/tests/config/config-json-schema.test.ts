import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import { CONFIG_SCHEMA, renderConfigSchema } from "./config-json-schema.ts";

describe("schemas/config-v1.json", () => {
  it("types blocks.<module>.options from the block manifests", async () => {
    // Compared as JSON: Oxfmt formats the file after the script writes it.
    expect(JSON.parse(await readFile(CONFIG_SCHEMA, "utf8"))).toEqual(
      JSON.parse(await renderConfigSchema()),
    );
  });
});
