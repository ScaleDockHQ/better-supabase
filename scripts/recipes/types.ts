/** The shapes `build-recipes.ts` reads from each recipe list. */
export const WEB_APP = "apps/examples/nextjs";
export const NATIVE_APP = "apps/examples/expo-powersync";

export interface Side {
  /** The example file, relative to the repo root. */
  readonly file: string;
  /** Web: shadcn components (`npx shadcn add ...`). Native: React Native primitives. */
  readonly components: readonly string[];
  /** `@better-supabase/<item>` registry items the snippet imports. */
  readonly glue: readonly string[];
}

/** A piece of UI inside a page, or a whole page. */
export type RecipeKind = "component" | "screen";

export interface RecipeSource {
  readonly slug: string;
  readonly title: string;
  /** The SQL modules the recipe uses. The first one sets its category. */
  readonly blocks: readonly [string, ...string[]];
  readonly kind: RecipeKind;
  /** Overrides the category of `blocks[0]`, such as `App tables` for recipes over the app's own tables. */
  readonly category?: "App tables";
  readonly description: string;
  /** The hook the code calls, and the entry it comes from. Server-rendered recipes have none. */
  readonly hook?: { readonly name: string; readonly entry: string };
  /** A recipe is available once its web side exists; native is optional. */
  readonly web?: Side;
  readonly native?: Side;
  /** A caveat shown under the install commands, such as a fix a registry component still needs. */
  readonly note?: string;
  /** For a planned recipe: what has to ship first. */
  readonly missing?: string;
}
