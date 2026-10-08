/** `betterSupabase` in `nuxt.config.ts`, or the module's inline options. */
export interface NuxtModuleOptions {
  /**
   * The server module whose default export is the entry array, e.g.
   * `'~~/server/better-supabase'` exporting `[withBetterSupabase(server)]`.
   * Without it the module registers no server middleware.
   */
  readonly server?: string;
  /** Auto-import the `better-supabase/vue` composables. Defaults to true. */
  readonly composables?: boolean;
}

/** A Nitro handler registration. */
export interface NitroHandlerLike {
  readonly handler: string;
  readonly middleware?: boolean;
  readonly route?: string;
}

/** An auto-import registration. */
export interface NuxtImportLike {
  readonly name: string;
  readonly from: string;
}

/** The part of the Nuxt instance the module writes, typed structurally. */
export interface NuxtLike {
  readonly options: {
    readonly betterSupabase?: NuxtModuleOptions | undefined;
    nitro: {
      virtual?: Record<string, string | (() => string)>;
      handlers?: NitroHandlerLike[];
    };
  };
  hook(name: "imports:extend", fn: (imports: NuxtImportLike[]) => void): void;
}

/** The composables `better-supabase/vue` exports, auto-imported in components. */
export const VUE_COMPOSABLES: readonly string[] = [
  "useAuth",
  "useSession",
  "useDb",
  "useLiveQuery",
  "useLiveCount",
  "useBroadcast",
  "usePresence",
  "useAction",
];

const MIDDLEWARE_ID = "#better-supabase/middleware";

/** The virtual Nitro middleware: the app's entries through `toH3V1`. */
export function middlewareSource(server: string): string {
  return [
    `import { defineEventHandler } from "h3";`,
    `import { toH3V1 } from "better-supabase/h3/v1";`,
    `import entries from ${JSON.stringify(server)};`,
    `export default defineEventHandler(toH3V1(entries));`,
  ].join("\n");
}

/** A Nuxt module, typed structurally so the package does not import `@nuxt/kit`. */
export interface BetterSupabaseNuxtModule {
  (inline: NuxtModuleOptions | undefined, nuxt: NuxtLike): void;
  getMeta(): Promise<{ readonly name: string; readonly configKey: string }>;
}

function setup(inline: NuxtModuleOptions | undefined, nuxt: NuxtLike): void {
  const options = { ...nuxt.options.betterSupabase, ...inline };
  if (options.server !== undefined) {
    const nitro = nuxt.options.nitro;
    nitro.virtual = {
      ...nitro.virtual,
      [MIDDLEWARE_ID]: middlewareSource(options.server),
    };
    nitro.handlers = [
      ...(nitro.handlers ?? []),
      { handler: MIDDLEWARE_ID, middleware: true },
    ];
  }
  if (options.composables ?? true) {
    nuxt.hook("imports:extend", (imports) => {
      for (const name of VUE_COMPOSABLES)
        imports.push({ name, from: "better-supabase/vue" });
    });
  }
}

/**
 * Registers the app's entries as Nitro server middleware (every
 * contribution on `event.context`) and auto-imports the Vue composables.
 *
 * ```ts title="nuxt.config.ts"
 * export default defineNuxtConfig({
 *   modules: ['better-supabase/nuxt'],
 *   betterSupabase: { server: '~~/server/better-supabase' },
 * })
 * ```
 */
const betterSupabaseNuxt: BetterSupabaseNuxtModule = Object.assign(setup, {
  getMeta: () =>
    Promise.resolve({ name: "better-supabase", configKey: "betterSupabase" }),
});

// oxlint-disable-next-line import/no-default-export -- Nuxt loads a module from its default export.
export default betterSupabaseNuxt;
