import { describe, expect, it } from "vitest";

import { encodePreset } from "../../src/preset/code.ts";
import { DEFAULT_CONVENTIONS } from "../../src/preset/fields.ts";
import {
  presetBlocksSource,
  presetConfigSource,
  presetInstallCommand,
} from "../../src/preset/render.ts";
import { resolvePreset } from "../../src/preset/resolve.ts";

describe("presetConfigSource", () => {
  it("lists every block, with the reason for those it adds", () => {
    const preset = {
      ...DEFAULT_CONVENTIONS,
      casing: "camel" as const,
      api: "api" as const,
      access: "provider" as const,
      integrations: ["next" as const],
      blocks: ["comments", "api-keys"],
    };
    expect(presetConfigSource(resolvePreset(preset))).toBe(
      [
        'import { defineConfig } from "better-supabase/config";',
        "",
        `// https://bettersupabase.com/create?preset=${encodePreset(preset)}`,
        "export default defineConfig({",
        '  casing: "camel",',
        '  sql: { api: "api" },',
        '  integrations: ["next"],',
        "  // The provider access model reads roles from your authorization",
        "  // library: set `authorization` to its adapter.",
        "  blocks: {",
        '    "updated-at": {}, // required by tenant',
        "    tenant: {}, // required by api-keys and comments",
        '    access: { model: "provider" }, // required by api-keys and comments',
        '    "api-keys": {},',
        "    comments: {},",
        "  },",
        "});",
        "",
      ].join("\n"),
    );
  });

  it("keeps a default preset short", () => {
    const source = presetConfigSource(
      resolvePreset({ ...DEFAULT_CONVENTIONS, blocks: ["profiles"] }),
    );
    expect(source).toContain("  blocks: {\n    profiles: {},\n  },");
    expect(source).not.toContain("casing");
  });
});

describe("presetBlocksSource", () => {
  it("wires the blocks with a client over the API schema", () => {
    const source = presetBlocksSource(
      resolvePreset({
        ...DEFAULT_CONVENTIONS,
        api: "api",
        blocks: ["comments", "ai-chat"],
      }),
    );
    expect(source).toContain(
      'import { commentsBlock } from "better-supabase/blocks/comments";',
    );
    expect(source).toContain('export const API_SCHEMA = "api";');
    expect(source).toContain("      aiChat: aiChatBlock,");
    expect(source).toContain(
      "transport: rpcTransport(supabase, { schema: API_SCHEMA }),",
    );
    // Blocks with only SQL (tenant, access) get no client.
    expect(source).not.toContain("tenantBlock");
  });

  it("calls the module schema without an API schema", () => {
    const source = presetBlocksSource(
      resolvePreset({ ...DEFAULT_CONVENTIONS, blocks: ["tags"] }),
    );
    expect(source).toContain("    { transport: rpcTransport(supabase) },");
    expect(source).not.toContain("API_SCHEMA");
  });
});

describe("presetInstallCommand", () => {
  it("adds the selected blocks, which bring what they require", () => {
    expect(
      presetInstallCommand(
        resolvePreset({ ...DEFAULT_CONVENTIONS, blocks: ["tags", "comments"] }),
      ),
    ).toBe("npx better-supabase sql add comments tags");
  });
});
