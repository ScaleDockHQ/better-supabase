import { describe, expect, it } from "vitest";

import { writeDesign } from "../../../src/cli/sql/design-edit.ts";

const source = (body: string): string =>
  `import { defineConfig } from 'better-supabase/config';\n\nexport default defineConfig({\n${body}\n});\n`;

describe("writeDesign", () => {
  it("writes the design's seeds into a JSON config", () => {
    const edit = writeDesign(
      "better-supabase.config.json",
      '{\n  "blocks": { "tags": {} }\n}\n',
      { seeds: { locale: "nl", variants: { tax: "nl" } } },
    );

    expect(edit.ok && JSON.parse(edit.text)).toEqual({
      blocks: { tags: {} },
      database: {
        seed: { defaults: { locale: "nl", variants: { tax: "nl" } } },
      },
    });
  });

  it("leaves a config without seeds as it is", () => {
    const text = '{\n  "blocks": { "tags": {} }\n}\n';

    expect(writeDesign("better-supabase.config.json", text, {})).toEqual({
      ok: true,
      text,
    });
  });

  it("says which key it can't set", () => {
    const seeds = writeDesign(
      "better-supabase.config.ts",
      source("  database: databaseConfig,"),
      { seeds: { locale: "nl" } },
    );

    expect(seeds.ok).toBe(false);
    expect(!seeds.ok && seeds.reason).toContain(
      "database.seed.defaults.locale",
    );
  });
});
