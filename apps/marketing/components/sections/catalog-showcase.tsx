import { ArrowRightIcon } from "lucide-react";

import { Section } from "@/components/sections/section";
import { LinkButton } from "@/components/site/link-button";
import { categoryHref, categoryStyle } from "@/features/blocks/categories";
import { BlockPreview } from "@/features/blocks/components/block-preview";
import { CategoryIcon } from "@/features/blocks/components/category-icon";
import { blockGroups, blocks } from "@/lib/blocks";
import { cn } from "@/lib/utils";

/** The block categories with their scenes, each linking to its section on `/blocks`. */
export function CatalogShowcase() {
  const groups = blockGroups();

  return (
    <Section
      id="blocks"
      eyebrow="Blocks"
      title="Add the features every SaaS needs as SQL you own"
      description={`${String(blocks.length)} blocks in ${String(groups.length)} categories: tables, policies, functions and a typed client for each. They install into your schema, so you read and change them like the rest of your code.`}
    >
      <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5">
        {groups.map((group) => {
          const style = categoryStyle(group.category);

          return (
            <li key={group.category}>
              <a
                href={categoryHref(group.category)}
                className="group flex h-full flex-col overflow-hidden rounded-xl border border-border bg-card transition-colors outline-none hover:border-foreground/20 focus-visible:ring-3 focus-visible:ring-ring/50"
              >
                <BlockPreview
                  category={group.category}
                  className="border-b border-border"
                />
                <span className="flex flex-1 flex-col gap-2 p-4">
                  <span className="flex items-center gap-2">
                    <CategoryIcon category={group.category} size="sm" />
                    <span className="text-sm font-medium">
                      {group.category}
                    </span>
                    <span
                      className={cn(
                        "ml-auto text-xs font-medium tabular-nums",
                        style.text,
                      )}
                    >
                      {group.blocks.length}
                    </span>
                  </span>
                  <span className="line-clamp-2 text-xs leading-5 text-muted-foreground">
                    {style.summary}
                  </span>
                </span>
              </a>
            </li>
          );
        })}
      </ul>
      <div className="flex flex-wrap gap-3 pt-8">
        <LinkButton href="/blocks">
          Browse the blocks
          <ArrowRightIcon aria-hidden="true" />
        </LinkButton>
        <LinkButton variant="outline" href="/create">
          Create an app from a preset
        </LinkButton>
      </div>
    </Section>
  );
}
