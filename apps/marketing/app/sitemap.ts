import type { MetadataRoute } from "next";

import { blockPath, blocks } from "@/lib/blocks";
import { availableRecipes, recipePath } from "@/lib/recipes";
import { site } from "@/lib/site";

const routes = [
  "",
  "/blocks",
  "/recipes",
  "/enterprise",
  "/contact",
  "/docs",
] as const;

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    ...routes,
    ...blocks.map((block) => blockPath(block.name)),
    ...availableRecipes.map((recipe) => recipePath(recipe.slug)),
  ].map((path) => ({ url: `${site.url}${path}` }));
}
