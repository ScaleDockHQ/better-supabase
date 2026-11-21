import { describe, expect, it } from "vitest";

import type { NuxtImportLike, NuxtLike } from "../../src/nuxt/index.ts";

import betterSupabaseNuxt, {
  middlewareSource,
  VUE_COMPOSABLES,
} from "../../src/nuxt/index.ts";
import * as vue from "../../src/vue/index.ts";

function fakeNuxt(betterSupabase?: NuxtLike["options"]["betterSupabase"]) {
  const hooks: ((imports: NuxtImportLike[]) => void)[] = [];

  const nuxt: NuxtLike = {
    options: { betterSupabase, nitro: {} },
    hook: (_name, fn) => {
      hooks.push(fn);
    },
  };

  const imports = (): NuxtImportLike[] => {
    const list: NuxtImportLike[] = [];

    for (const hook of hooks) {
      hook(list);
    }

    return list;
  };

  return { nuxt, imports };
}

describe("better-supabase/nuxt", () => {
  it("registers the entries as Nitro middleware through a virtual module", () => {
    const { nuxt, imports } = fakeNuxt({ server: "~~/server/better-supabase" });
    betterSupabaseNuxt(undefined, nuxt);
    expect(nuxt.options.nitro.handlers).toEqual([
      { handler: "#better-supabase/middleware", middleware: true },
    ]);
    expect(nuxt.options.nitro.virtual?.["#better-supabase/middleware"]).toBe(
      middlewareSource("~~/server/better-supabase"),
    );
    expect(imports().map((entry) => entry.name)).toEqual([...VUE_COMPOSABLES]);
  });

  it("auto-imports only names better-supabase/vue exports", () => {
    for (const name of VUE_COMPOSABLES) {
      expect(vue).toHaveProperty(name);
    }
  });

  it("prefers inline options and can skip the composables", () => {
    const { nuxt, imports } = fakeNuxt({ server: "~~/a" });
    betterSupabaseNuxt({ server: "~~/b", composables: false }, nuxt);
    expect(
      nuxt.options.nitro.virtual?.["#better-supabase/middleware"],
    ).toContain('"~~/b"');
    expect(imports()).toEqual([]);
  });

  it("registers nothing on the server without a server module", async () => {
    const { nuxt } = fakeNuxt();
    betterSupabaseNuxt(undefined, nuxt);
    expect(nuxt.options.nitro.handlers).toBeUndefined();
    expect(await betterSupabaseNuxt.getMeta()).toEqual({
      name: "better-supabase",
      configKey: "betterSupabase",
    });
  });

  it("writes the h3 v2 bridge for Nitro 3, from either place Nuxt reports it", () => {
    const expected = middlewareSource("~~/server/bsb", 3);

    expect(expected).toBe(
      [
        'import { toH3 } from "better-supabase/h3";',
        'import entries from "~~/server/bsb";',
        "export default toH3(entries);",
      ].join("\n"),
    );

    for (const patch of [
      (nuxt: object & { options: object }) =>
        Object.assign(nuxt.options, { _nitroMajor: 3 }),
      (nuxt: object) =>
        Object.assign(nuxt, { _nitro: { meta: { majorVersion: 3 } } }),
    ]) {
      const { nuxt } = fakeNuxt({ server: "~~/server/bsb" });
      patch(nuxt);
      betterSupabaseNuxt(undefined, nuxt);
      expect(nuxt.options.nitro.virtual?.["#better-supabase/middleware"]).toBe(
        expected,
      );
    }
  });

  it("writes middleware that imports the h3 v1 bridge", () => {
    expect(middlewareSource("~~/server/bsb")).toBe(
      [
        'import { defineEventHandler } from "h3";',
        'import { toH3V1 } from "better-supabase/h3/v1";',
        'import entries from "~~/server/bsb";',
        "export default defineEventHandler(toH3V1(entries));",
      ].join("\n"),
    );
  });
});
