import type { Route } from "next";

import { BlocksIcon, LayoutTemplateIcon, WandSparklesIcon } from "lucide-react";

import { categoryStyle } from "@/features/blocks/categories";
import { CategoryIcon } from "@/features/blocks/components/category-icon";
import { blockGroups, blockPath } from "@/lib/blocks";

import { CatalogLink } from "./catalog-link";

const OVERVIEW = [
  { href: "/blocks", label: "All blocks", icon: BlocksIcon },
  { href: "/recipes", label: "Recipes", icon: LayoutTemplateIcon },
  { href: "/create", label: "Create an app", icon: WandSparklesIcon },
] as const satisfies readonly { href: Route; label: string; icon: unknown }[];

/**
 * The catalog sidebar: the overview pages, then every block under its
 * category. It renders on the server; only the links read the pathname.
 */
export function CatalogNav() {
  return (
    <nav aria-label="Catalog" className="flex flex-col gap-6 text-sm">
      <ul className="flex flex-col gap-0.5">
        {OVERVIEW.map(({ href, label, icon: Icon }) => (
          <li key={href}>
            <CatalogLink href={href}>
              <Icon aria-hidden="true" className="size-4" />
              {label}
            </CatalogLink>
          </li>
        ))}
      </ul>
      {blockGroups().map((group) => {
        const headingId = `nav-${categoryStyle(group.category).slug}`;

        return (
          <section
            key={group.category}
            aria-labelledby={headingId}
            className="flex flex-col gap-1"
          >
            <h2
              id={headingId}
              className="flex items-center gap-2 px-2 text-xs font-medium text-muted-foreground"
            >
              <CategoryIcon category={group.category} size="sm" />
              {group.category}
              <span className="ml-auto tabular-nums">
                {group.blocks.length}
              </span>
            </h2>
            <ul className="ml-4.5 flex flex-col gap-0.5 border-l border-border pl-2">
              {group.blocks.map((block) => (
                <li key={block.name}>
                  <CatalogLink href={blockPath(block.name)} className="min-h-7">
                    {block.title}
                  </CatalogLink>
                </li>
              ))}
            </ul>
          </section>
        );
      })}
    </nav>
  );
}
