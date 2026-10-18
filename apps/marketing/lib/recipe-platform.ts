// Kept apart from `recipes.ts`, which loads the recipe and catalog JSON, so
// the client tabs can import it.

export type RecipePlatform = "web" | "native";

export const recipePlatforms: readonly RecipePlatform[] = ["web", "native"];

/** Reads `?platform=`; anything but `native` is the web. */
export function parsePlatform(value: string | null): RecipePlatform {
  return value === "native" ? "native" : "web";
}
