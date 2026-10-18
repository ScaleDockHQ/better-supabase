import { BlocksIcon } from "lucide-react";

import { CatalogLink } from "@/features/catalog/components/catalog-link";
import { blockGroups, blockPath } from "@/lib/blocks";

import { categoryStyle } from "../categories";
import { BlockIcon } from "./block-icon";
import { CategoryIcon } from "./category-icon";

/**
 * The `/blocks` sidebar: the overview, then every block under its category.
 * It renders on the server; only the links read the pathname.
 */
export function BlocksNav() {
  return (
    <nav aria-label="Blocks" className="flex flex-col gap-6 text-sm">
      <CatalogLink href="/blocks">
        <BlocksIcon aria-hidden="true" className="size-4" />
        All blocks
      </CatalogLink>
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
            <ul className="flex flex-col gap-0.5">
              {group.blocks.map((block) => (
                <li key={block.name}>
                  <CatalogLink href={blockPath(block.name)} className="min-h-7">
                    <BlockIcon
                      name={block.name}
                      category={block.category}
                      size="xs"
                    />
                    <span className="truncate">{block.title}</span>
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
