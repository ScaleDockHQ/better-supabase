import { describe, expect, it } from "vitest";

import {
  createUrl,
  presetApplyCommand,
  presetConfigSource,
  presetInstallCommand,
} from "../../src/preset/design.ts";
import { DEFAULT_CONVENTIONS } from "../../src/preset/fields.ts";
import { namedPreset } from "../../src/preset/presets.ts";
import { presetBlocksSource } from "../../src/preset/render.ts";
import { resolvePreset } from "../../src/preset/resolve.ts";

describe("presetConfigSource", () => {
  it("lists every block, with the reason for those it adds", async () => {
    const preset = {
      ...DEFAULT_CONVENTIONS,
      casing: "camel" as const,
      api: "api" as const,
      access: "provider" as const,
      integrations: ["next" as const],
      blocks: ["comments", "api-keys"],
    };

    const resolved = resolvePreset(preset);

    expect(await presetConfigSource(resolved)).toBe(
      [
        'import { defineConfig } from "better-supabase/config";',
        "",
        `// ${await createUrl(resolved)}`,
        "export default defineConfig({",
        '  database: { sql: { api: "api" } },',
        '  gen: { casing: "camel" },',
        '  adapters: ["next"],',
        "  // The provider access model reads roles from your authorization",
        "  // library: set `auth.authorization` to its adapter.",
        "  blocks: {",
        '    "updated-at": {}, // required by tenant',
        "    tenant: {}, // required by api-keys, comments and messaging",
        '    access: { model: "provider" }, // required by api-keys, comments, subjects and messaging',
        '    "api-keys": {},',
        "    comments: {},",
        "    subjects: {}, // required by comments and messaging",
        "    messaging: {}, // required by comments",
        "  },",
        "});",
        "",
      ].join("\n"),
    );
  });

  it("keeps a default preset short", async () => {
    const source = await presetConfigSource(
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
  it("start or apply a named preset by its name", async () => {
    const resolved = resolvePreset(namedPreset("crm"));

    expect(await presetInstallCommand(resolved)).toBe(
      "npx better-supabase init --preset crm",
    );
    expect(await presetApplyCommand(resolved)).toBe(
      "npx better-supabase add --preset crm",
    );
  });

  it("start or apply another preset by its /create URL", async () => {
    const resolved = resolvePreset({
      ...DEFAULT_CONVENTIONS,
      blocks: ["tags", "comments"],
    });

    const url = await createUrl(resolved);

    expect(url).toMatch(
      /^https:\/\/app\.bettersupabase\.com\/create\?design=0/,
    );
    expect(await presetInstallCommand(resolved)).toBe(
      `npx better-supabase init --preset "${url}"`,
    );
    expect(await presetApplyCommand(resolved)).toBe(
      `npx better-supabase add --preset "${url}"`,
    );
  });
});
