import {
  namedPreset,
  type Preset,
  PRESET_FIELDS,
  PRESET_FRAMEWORKS,
  PRESET_NAMES,
  PRESETS,
  presetConfigSource,
  resolvePreset,
} from "better-supabase/preset";
import { describe, expect, test } from "vitest";

import { createHref, PACKAGE_MANAGERS } from "../../lib/create";
import {
  AUTH_CHOICE_INFO,
  AUTH_CHOICES,
  authChoiceOf,
  CONVENTION_KEYS,
  CONVENTION_VALUES,
  CUSTOM_PRESET,
  FIELD_LABELS,
  fieldLabel,
  FRAMEWORKS,
  impliedIntegrations,
  impliedNote,
  initialAuthz,
  INTEGRATION_ORDER,
  INTEGRATIONS,
  permDockGenerate,
  permDockInstall,
  PLATFORM_LABELS,
  PLATFORMS,
  PRESET_ITEMS,
  platformsFor,
  platformUnavailable,
  withAuthChoice,
  withFramework,
  withPermDock,
} from "../../lib/create-options";

const saas = namedPreset("saas");

function valuesOf(key: string): readonly string[] {
  return PRESET_FIELDS.find((field) => field.key === key)?.values ?? [];
}

describe("labels", () => {
  test("cover every framework, platform and convention value", () => {
    expect(Object.keys(FRAMEWORKS).toSorted()).toEqual(
      [...PRESET_FRAMEWORKS].toSorted(),
    );
    expect(Object.keys(PLATFORM_LABELS).toSorted()).toEqual(
      [...valuesOf("platforms")].toSorted(),
    );

    for (const key of CONVENTION_KEYS) {
      expect(Object.keys(CONVENTION_VALUES[key]).toSorted()).toEqual(
        [...valuesOf(key)].toSorted(),
      );
    }
  });

  test("cover every field, access model and integration", () => {
    expect(Object.keys(FIELD_LABELS).toSorted()).toEqual(
      PRESET_FIELDS.map((field) => field.key).toSorted(),
    );
    expect(
      [
        ...new Set(AUTH_CHOICES.map((each) => AUTH_CHOICE_INFO[each].access)),
      ].toSorted(),
    ).toEqual([...valuesOf("access")].toSorted());
    expect([...INTEGRATION_ORDER].toSorted()).toEqual(
      [...valuesOf("integrations")].toSorted(),
    );
    expect(Object.keys(INTEGRATIONS).toSorted()).toEqual(
      [...valuesOf("integrations")].toSorted(),
    );
  });

  test("name a field for the conflicts list", () => {
    expect(fieldLabel("platforms")).toBe("Platforms");
    expect(fieldLabel("scope")).toBe("Row ownership");
    expect(fieldLabel("unknown")).toBe("unknown");
  });
});

describe("platforms", () => {
  test("match the library's conflicts for every framework and platform", () => {
    for (const framework of PRESET_FRAMEWORKS) {
      for (const platforms of PLATFORMS) {
        const { conflicts } = resolvePreset({ ...saas, framework, platforms });
        const valid = platformsFor(framework).includes(platforms);

        expect(
          conflicts.some((conflict) => conflict.field !== undefined),
          `${framework} on ${platforms}`,
        ).toBe(!valid);
        expect(platformUnavailable(framework, platforms) === undefined).toBe(
          valid,
        );
      }
    }
  });

  test("move to a valid value when the framework changes", () => {
    const web: Preset = { ...saas, framework: "next", platforms: "web" };
    expect(withFramework(web, "expo").platforms).toBe("native");
    expect(withFramework({ ...web, platforms: "both" }, "expo").platforms).toBe(
      "both",
    );

    const native = withFramework(web, "expo");
    expect(withFramework(native, "vite")).toMatchObject({
      framework: "vite",
      platforms: "web",
    });

    for (const from of PRESET_FRAMEWORKS) {
      for (const to of PRESET_FRAMEWORKS) {
        const start = withFramework(saas, from);
        const { conflicts } = resolvePreset(withFramework(start, to));
        expect(conflicts.filter((each) => each.field !== undefined)).toEqual(
          [],
        );
      }
    }
  });
});

describe("auth choices", () => {
  test("keep PermDock as marketing state next to the provider access model", () => {
    const { preset, authz } = withAuthChoice(saas, "permdock");
    expect(preset.access).toBe("provider");
    expect(authz).toBe("permdock");
    expect(authChoiceOf(preset, authz)).toBe("permdock");
    expect(authChoiceOf(preset, undefined)).toBe("provider");
    expect(withAuthChoice(preset, "roles")).toEqual({
      preset: { ...preset, access: "roles" },
      authz: undefined,
    });
  });

  test("round trip through the URL", () => {
    const { preset, authz } = withAuthChoice(saas, "permdock");
    const url = new URL(createHref(preset, "apps/web", authz), "https://x.dev");
    expect(url.searchParams.get("authz")).toBe("permdock");
    expect(initialAuthz(url.searchParams.get("authz"), preset)).toBe(
      "permdock",
    );
    expect(initialAuthz("permdock", saas)).toBeUndefined();
    expect(initialAuthz("other", preset)).toBeUndefined();
    expect(initialAuthz(null, preset)).toBeUndefined();
  });
});

describe("integrations", () => {
  test("lock the framework's own integration and what it requires", () => {
    expect([...impliedIntegrations("next")]).toEqual([
      ["next", "framework"],
      ["client", "required"],
    ]);
    expect([...impliedIntegrations("hono")]).toEqual([["hono", "framework"]]);
    expect([...impliedIntegrations("vite")]).toEqual([]);
    expect(impliedNote("framework", "next")).toBe("Added for Next.js");
    expect(impliedNote("required", "expo")).toBe("Needed by Expo");
  });
});

describe("PermDock setup", () => {
  test("adds the package in the app or its workspace package", () => {
    expect(
      PACKAGE_MANAGERS.map((each) => permDockInstall(each, undefined)),
    ).toEqual([
      "pnpm add permdock",
      "npm install permdock",
      "yarn add permdock",
      "bun add permdock",
    ]);
    expect(permDockInstall("pnpm", "apps/web")).toBe(
      "pnpm add permdock --filter ./apps/web",
    );
    expect(permDockInstall("npm", "apps/web")).toBe(
      "npm install permdock --workspace apps/web",
    );
  });

  test("runs permdock through the package manager", () => {
    const commands = permDockGenerate("pnpm");
    expect(commands.at(-1)).toBe(
      "pnpm exec permdock catalog --out permissions.catalog.json",
    );
    expect(commands).toContain(
      "supabase db schema declarative sync --no-apply -f permdock",
    );
  });

  test("puts the provider in the config where the comment was", () => {
    const source = presetConfigSource(
      resolvePreset({ ...saas, access: "provider" }),
    );

    const out = withPermDock(source);

    expect(out).not.toContain("set `authorization` to its adapter");
    expect(out.split("\n").slice(0, 6)).toEqual([
      'import { readFileSync } from "node:fs";',
      'import { defineConfig } from "better-supabase/config";',
      'import { authorizationProvider } from "permdock/better-supabase";',
      "",
      "const read = (file: string) =>",
      '  readFileSync(new URL(file, import.meta.url), "utf8");',
    ]);
    expect(out).toContain(
      [
        "  authorization: authorizationProvider({",
        '    manifest: read("permdock.manifest.json"),',
        '    catalog: read("permissions.catalog.json"),',
        "  }),",
      ].join("\n"),
    );
    expect(withPermDock(presetConfigSource(resolvePreset(saas)))).toBe(
      presetConfigSource(resolvePreset(saas)),
    );
  });
});

describe("preset items", () => {
  test("list every named preset with a title and a description, then Custom", () => {
    expect(PRESET_ITEMS.map((item) => item.value)).toEqual([
      ...PRESET_NAMES,
      CUSTOM_PRESET.value,
    ]);

    for (const name of PRESET_NAMES) {
      expect(PRESETS[name].title).not.toBe("");
      expect(PRESETS[name].description).not.toBe("");
    }

    expect(PRESET_NAMES).not.toContain(CUSTOM_PRESET.value);
  });
});
