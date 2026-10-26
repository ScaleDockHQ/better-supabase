import { describe, expect, it } from "vitest";

import { writeDesign } from "../../../src/cli/sql/design-edit.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const source = (body: string): string =>
  `import { defineConfig } from 'better-supabase/config';\n\nexport default defineConfig({\n${body}\n});\n`;

describe("writeDesign", () => {
  it("merges extra columns over the ones the config has", () => {
    const config = resolveConfig(
      { blocks: { tags: { options: { extraColumns: { color: "text" } } } } },
      "/app",
    );

    const edit = writeDesign(
      "better-supabase.config.json",
      '{\n  "blocks": { "tags": {} }\n}\n',
      { extraColumns: { tags: { weight: "integer" } } },
      config,
    );

    expect(edit.ok && JSON.parse(edit.text)).toEqual({
      blocks: {
        tags: {
          options: { extraColumns: { color: "text", weight: "integer" } },
        },
      },
    });
  });

  it("says which key it can't set", () => {
    const blocks = writeDesign(
      "better-supabase.config.ts",
      source("  blocks: { tags: tagsBlock },"),
      { extraColumns: { tags: { color: "text" } } },
    );

    expect(blocks.ok).toBe(false);
    expect(!blocks.ok && blocks.reason).toContain(
      "blocks.tags.options.extraColumns can't be set",
    );
  });
});
