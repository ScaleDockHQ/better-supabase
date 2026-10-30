import { describe, expect, it } from "vitest";

import type { PresetSpec } from "../../src/preset/spec.ts";

import { defineConfig, resolveConfig } from "../../src/config/index.ts";
import { expandPreset, presetOf } from "../../src/preset/config.ts";
import { DEFAULT_CONVENTIONS } from "../../src/preset/fields.ts";
import { namedPreset, PRESET_NAMES } from "../../src/preset/presets.ts";
import {
  presetFromSpec,
  presetOfSpec,
  presetSpec,
} from "../../src/preset/spec.ts";

describe("presetOf", () => {
  it("reads a name, a /create URL and an object", () => {
    expect(presetOf("saas")).toEqual(namedPreset("saas"));
    expect(presetOf("consumer").scope).toBe("user");
    expect(presetOf({ casing: "camel", blocks: ["tags"] })).toEqual({
      ...DEFAULT_CONVENTIONS,
      casing: "camel",
      blocks: ["tags"],
    });
    expect(
      presetOf("https://app.bettersupabase.com/create?preset=crm#graph"),
    ).toEqual(namedPreset("crm"));
    expect(presetOf({ api: "api" })).toEqual({
      ...DEFAULT_CONVENTIONS,
      api: "api",
      blocks: [],
    });
  });

  it("names the presets when the input is none of them", () => {
    expect(() => presetOf("startup")).toThrow(
      `preset: "startup" is not a preset name. Use one of ${PRESET_NAMES.join(", ")}, or an object of conventions and blocks.`,
    );
  });

  it("names the codemod for a 0.14 preset code", () => {
    expect(() => presetOf("1pWEF3d578B1iGt16")).toThrow(
      /better-supabase codemod 0\.15/,
    );
  });

  it("names the key or value an object gets wrong", () => {
    expect(() => presetOfSpec({ casing: "kebab" })).toThrow(
      "preset.casing: expected one of",
    );
    expect(() => presetOfSpec({ colour: "red" })).toThrow(
      "preset.colour: not a preset key.",
    );
  });
});

describe("expandPreset", () => {
  it("leaves a config without a preset alone", () => {
    const config = { blocks: ["tags"] };
    expect(expandPreset(config)).toBe(config);
  });

  it("expands the blocks and the conventions that differ from the defaults", () => {
    const code: PresetSpec = {
      blocks: ["comments"],
      casing: "camel",
      api: "api",
      access: "catalog",
      idType: "bigint",
      integrations: ["next"],
    };

    expect(expandPreset({ preset: code })).toEqual({
      preset: code,
      gen: { casing: "camel" },
      database: { sql: { api: "api" } },
      adapters: ["next"],
      blocks: {
        "updated-at": {},
        memberships: {},
        permissions: { model: "catalog", idType: "bigint" },
        comments: {},
        subjects: {},
        messaging: {},
      },
    });
  });

  it("lets explicit config win", () => {
    const code: PresetSpec = {
      blocks: ["permissions"],
      casing: "camel",
      api: "api",
      access: "catalog",
    };

    const expanded = expandPreset({
      preset: code,
      gen: { casing: "snake" },
      database: { sql: { schema: "app" } },
      blocks: {
        permissions: { idType: "text" },
        tags: { ownership: "managed" },
      },
    });

    expect(expanded.gen?.casing).toBe("snake");
    expect(expanded.database?.sql).toEqual({ api: "api", schema: "app" });
    expect(expanded.blocks).toEqual({
      "updated-at": {},
      memberships: {},
      permissions: { model: "catalog", idType: "text" },
      tags: { ownership: "managed" },
    });
    // Expanding again gives the same config.
    expect(expandPreset(expanded)).toEqual(expanded);
  });

  it("takes a list of blocks next to the preset", () => {
    expect(
      expandPreset({ preset: "minimal", blocks: ["tags"] }).blocks,
    ).toEqual({ profiles: {}, tags: {} });
  });

  it("throws on what can't install", () => {
    const code: PresetSpec = { blocks: ["organizations"], scope: "user" };
    expect(() => expandPreset({ preset: code })).toThrow(
      `preset: organizations (it needs tenants, and scope "user" has none) can't install.`,
    );
    const expo: PresetSpec = { framework: "expo", blocks: [] };
    expect(() => expandPreset({ preset: expo })).toThrow(
      "preset: platforms (Expo builds a native app: choose native or both) can't install.",
    );
  });
});

describe("conventions", () => {
  it("write database.sql.owner and the tenant name when they differ from the defaults", () => {
    const user = expandPreset({ preset: { blocks: ["tags"], scope: "user" } });

    expect(user.database?.sql).toEqual({ owner: "user" });
    expect(user.blocks).toEqual({ tags: {} });

    const workspace = expandPreset({
      preset: {
        blocks: ["organizations"],
        tenantName: "workspace",
        api: "api",
      },
    });

    expect(workspace.database?.sql).toEqual({ api: "api" });
    expect(workspace.blocks).toMatchObject({
      memberships: { names: { organization: "workspace" } },
    });
    expect(expandPreset({ preset: "minimal" }).database).toBeUndefined();
  });
});

describe("defineConfig and resolveConfig", () => {
  it("expand the preset", () => {
    const config = defineConfig({ preset: "minimal" });
    expect(config.blocks).toEqual({ profiles: {} });
    const resolved = resolveConfig({ preset: "minimal" }, "/app");
    expect(resolved.blockNames).toEqual(["profiles"]);
    expect(resolveConfig(config, "/app").blockNames).toEqual(["profiles"]);
  });
});

describe("preset instances", () => {
  it("write a selected block's names and another instance of a block", () => {
    const resolved = resolveConfig({ preset: "property" }, "/app");
    const maintenance = resolved.instances["maintenance"];
    expect(maintenance?.block).toBe("tasks");
    expect(maintenance?.config.entities).toEqual({
      task: "maintenance_request",
    });
    expect(resolved.instances["tasks"]).toBeUndefined();

    const helpdesk = resolveConfig({ preset: "helpdesk" }, "/app");
    expect(helpdesk.instances["tasks"]?.config.entities).toEqual({
      task: "ticket",
      project: "issue",
    });
  });

  it("round-trip through a preset object", () => {
    const preset = {
      ...namedPreset("saas"),
      instances: { labels: { block: "tags" } },
    };

    const spec = presetSpec(preset);
    expect(spec).toMatchObject({ instances: { labels: { block: "tags" } } });
    expect(presetFromSpec(spec)).toEqual(preset);
  });

  it("reject a key an instance doesn't take", () => {
    expect(() =>
      presetFromSpec({ instances: { labels: { kind: "tags" } } }),
    ).toThrow("preset.instances.labels.kind: not an instance key");
  });
});
