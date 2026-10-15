import type { MetadataRoute } from "next";

import { blockPath, blocks } from "@/lib/blocks";
import { site } from "@/lib/site";

const routes = [
  "",
  "/blocks",
  "/recipes",
  "/create",
  "/changelog",
  "/enterprise",
  "/docs",
] as const;

export default function sitemap(): MetadataRoute.Sitemap {
  return [...routes, ...blocks.map((block) => blockPath(block.name))].map(
    (path) => ({ url: `${site.url}${path}` }),
  );
}
