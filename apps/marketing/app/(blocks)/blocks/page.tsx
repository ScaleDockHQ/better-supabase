import type { Metadata } from "next";

import { categoryHref } from "@/features/blocks/categories";
import { BlockSearch } from "@/features/blocks/components/block-search";
import { CategoryIcon } from "@/features/blocks/components/category-icon";
import { CategorySection } from "@/features/blocks/components/category-section";
import { PageHeader } from "@/features/catalog/components/page-header";
import { blockGroups, blockSummaries } from "@/lib/blocks";

export const metadata: Metadata = {
  title: "Blocks",
  description:
    "Every better-supabase block: the SQL module, what it needs, the modes it supports and the events it writes.",
  alternates: { canonical: "/blocks" },
};

export default function BlocksPage() {
  const blocks = blockSummaries();
  const groups = blockGroups();

  return (
    <div className="flex flex-col gap-10">
      <PageHeader eyebrow="Blocks" title="Pick the features your app needs">
        <p>
          Each block is a SQL module in your schema, with a TypeScript side for
          most of them. Install one with{" "}
          <code className="font-mono text-code text-foreground">
            npx better-supabase add
          </code>
          , and the modules it needs come with it. This list is built from the
          module registry, so it matches the package: {blocks.length} blocks in{" "}
          {groups.length} categories.
        </p>
      </PageHeader>

      <nav aria-label="Categories">
        <ul className="flex flex-wrap gap-2">
          {groups.map((group) => (
            <li key={group.category}>
              <a
                href={categoryHref(group.category)}
                className="flex items-center gap-2 rounded-full border border-border py-1 pr-3 pl-1 text-sm transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
              >
                <CategoryIcon category={group.category} size="sm" />
                {group.category}
                <span className="text-xs text-muted-foreground tabular-nums">
                  {group.blocks.length}
                </span>
              </a>
            </li>
          ))}
        </ul>
      </nav>

      <BlockSearch blocks={blocks}>
        <div className="flex flex-col gap-14">
          {groups.map((group) => (
            <CategorySection key={group.category} group={group} />
          ))}
        </div>
      </BlockSearch>
    </div>
  );
}
