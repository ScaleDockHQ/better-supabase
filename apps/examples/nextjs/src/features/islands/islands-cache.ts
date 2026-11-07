/** `?scope=remote` reads through `"use cache: remote"`; the default is private. */
export type IslandScope = "private" | "remote";

export function islandScope(value: string | string[] | undefined): IslandScope {
  return value === "remote" ? "remote" : "private";
}
