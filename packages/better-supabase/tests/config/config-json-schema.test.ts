import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import { CONFIG_SCHEMA, renderConfigSchema } from "./config-json-schema.ts";

describe("schemas/config-v1.json", () => {
  it("is rendered from the config schema and the block manifests", async () => {
    // Compared as JSON: Oxfmt formats the file after the script writes it.
    expect(JSON.parse(await readFile(CONFIG_SCHEMA, "utf-8"))).toEqual(
      JSON.parse(renderConfigSchema()),
    );
  });

  it("describes ownTablePolicies globally and on every block entry", () => {
    const found: unknown[] = [];

    const walk = (node: unknown): void => {
      if (Array.isArray(node)) {
        for (const item of node) {
          walk(item);
        }
      } else if (typeof node === "object" && node !== null) {
        for (const [key, value] of Object.entries(node)) {
          if (key === "ownTablePolicies") {
            found.push(value);
          }

          walk(value);
        }
      }
    };

    walk(JSON.parse(renderConfigSchema()));

    expect(found.length).toBeGreaterThanOrEqual(3);

    for (const entry of found) {
      expect(entry).toMatchObject({
        enum: ["block", "app"],
        description: expect.stringContaining(
          "bsb_ policy, permissive or restrictive",
        ),
      });
    }

    expect(found).toContainEqual(expect.objectContaining({ default: "block" }));
  });
});
