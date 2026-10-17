import { describe, expect, it } from "vitest";

import { encodePreset } from "../../src/preset/code.ts";
import { DEFAULT_CONVENTIONS } from "../../src/preset/fields.ts";
import {
  presetApplyCommand,
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
  it("wires the blocks with a client through the generated config", () => {
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
    expect(source).toContain(
      'import { blockConfig } from "./supabase/blocks.generated";',
    );
    expect(source).toContain(
      "export const blockSet = defineBlocks(blockConfig, {",
    );
    expect(source).toContain("  aiChat: aiChatBlock,");
    expect(source).toContain(
      "return blockSet.create({ transport: rpcTransport(supabase) });",
    );
    // The API schema comes from blocks.generated.ts, not the wiring.
    expect(source).not.toContain("API_SCHEMA");
    // Blocks with only SQL (tenant, access) get no client.
    expect(source).not.toContain("tenantBlock");
  });

  it("imports the generated config from the path it is given", () => {
    const source = presetBlocksSource(
      resolvePreset({ ...DEFAULT_CONVENTIONS, blocks: ["tags"] }),
      "./db/blocks.generated.ts",
    );

    expect(source).toContain(
      'import { blockConfig } from "./db/blocks.generated.ts";',
    );
  });
});

describe("presetInstallCommand and presetApplyCommand", () => {
  it("start or apply the preset by its code", () => {
    const preset = { ...DEFAULT_CONVENTIONS, blocks: ["tags", "comments"] };
    const resolved = resolvePreset(preset);
    expect(presetInstallCommand(resolved)).toBe(
      `npx better-supabase init --preset ${encodePreset(preset)}`,
    );
    expect(presetApplyCommand(resolved)).toBe(
      `npx better-supabase apply --preset ${encodePreset(preset)}`,
    );
  });
});
