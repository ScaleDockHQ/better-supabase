import { describe, expect, it } from "vitest";

import { defineConfig, resolveConfig } from "../../src/config/index.ts";
import { encodePreset } from "../../src/preset/code.ts";
import { expandPreset, presetOf } from "../../src/preset/config.ts";
import { DEFAULT_CONVENTIONS } from "../../src/preset/fields.ts";
import { namedPreset, PRESET_NAMES } from "../../src/preset/presets.ts";

describe("presetOf", () => {
  it("reads a name, a code, a /create URL and an object", () => {
    expect(presetOf("saas")).toEqual(namedPreset("saas"));
    expect(presetOf("consumer").scope).toBe("user");
    const code = encodePreset({ casing: "camel", blocks: ["tags"] });
    expect(presetOf(code)).toEqual({
      ...DEFAULT_CONVENTIONS,
      casing: "camel",
      blocks: ["tags"],
    });
    expect(
      presetOf(`https://bettersupabase.com/create?preset=${code}#graph`),
    ).toEqual(presetOf(code));
    expect(presetOf({ api: "api" })).toEqual({
      ...DEFAULT_CONVENTIONS,
      api: "api",
      blocks: [],
    });
  });

  it("names the presets when the input is none of them", () => {
    expect(() => presetOf("startup")).toThrow(
      `preset: "startup" is not a preset. Use a name (${PRESET_NAMES.join(", ")}), a code from /create, or its URL.`,
    );
  });
});

describe("expandPreset", () => {
  it("leaves a config without a preset alone", () => {
    const config = { blocks: ["tags"] };
    expect(expandPreset(config)).toBe(config);
  });

  it("expands the blocks and the conventions that differ from the defaults", () => {
    const code = encodePreset({
      blocks: ["comments"],
      casing: "camel",
      api: "api",
      access: "catalog",
      idType: "bigint",
      integrations: ["next"],
    });

    expect(expandPreset({ preset: code })).toEqual({
      preset: code,
      casing: "camel",
      sql: { api: "api" },
      integrations: ["next"],
      blocks: {
        "updated-at": {},
        tenant: {},
        access: { model: "catalog", idType: "bigint" },
        comments: {},
      },
    });
  });

  it("lets explicit config win", () => {
    const code = encodePreset({
      blocks: ["access"],
      casing: "camel",
      api: "api",
      access: "catalog",
    });

    const expanded = expandPreset({
      preset: code,
      casing: "snake",
      sql: { schema: "app" },
      blocks: {
        access: { idType: "text" },
        tags: { mode: "managed" },
      },
    });

    expect(expanded.casing).toBe("snake");
    expect(expanded.sql).toEqual({ api: "api", schema: "app" });
    expect(expanded.blocks).toEqual({
      "updated-at": {},
      tenant: {},
      access: { model: "catalog", idType: "text" },
      tags: { mode: "managed" },
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
    const code = encodePreset({ blocks: ["organizations"], scope: "user" });
    expect(() => expandPreset({ preset: code })).toThrow(
      `preset: organizations (it needs tenants, and scope "user" has none) can't install.`,
    );
    const expo = encodePreset({ framework: "expo", blocks: [] });
    expect(() => expandPreset({ preset: expo })).toThrow(
      "preset: platforms (Expo builds a native app: choose native or both) can't install.",
    );
  });
});

describe("conventions", () => {
  it("write sql.scope and sql.naming when they differ from the defaults", () => {
    const user = expandPreset({
      preset: encodePreset({ blocks: ["tags"], scope: "user" }),
    });

    expect(user.sql).toEqual({ scope: "user" });
    expect(user.blocks).toEqual({ tags: {} });

    const workspace = expandPreset({
      preset: encodePreset({
        blocks: ["organizations"],
        tenantName: "workspace",
        api: "api",
      }),
    });

    expect(workspace.sql).toEqual({
      api: "api",
      naming: { tenant: "workspace" },
    });
    expect(expandPreset({ preset: "minimal" }).sql).toBeUndefined();
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
