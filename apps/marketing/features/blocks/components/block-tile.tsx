import { ArrowUpRightIcon } from "lucide-react";

import type { BlockSummary } from "@/lib/block-filter";

import { Badge } from "@/components/reui/badge";
import { SiteLink } from "@/components/site/site-link";
import { blockPath } from "@/lib/blocks";

import { CategoryIcon } from "./category-icon";

/** One block in a grid: icon, title, package name and the first lines of its description. */
export function BlockTile({ block }: { block: BlockSummary }) {
  return (
    <SiteLink
      href={blockPath(block.name)}
      className="group flex h-full flex-col gap-3 rounded-xl border border-border bg-card p-4 transition-colors outline-none hover:border-foreground/20 hover:bg-muted/40 focus-visible:ring-3 focus-visible:ring-ring/50"
    >
      <span className="flex items-center gap-3">
        <CategoryIcon category={block.category} />
        <span className="flex min-w-0 flex-col">
          <span className="truncate text-sm font-medium">{block.title}</span>
          <span className="truncate font-mono text-xs text-muted-foreground">
            {block.name}
          </span>
        </span>
        <ArrowUpRightIcon
          aria-hidden="true"
          className="ml-auto size-4 shrink-0 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100"
        />
      </span>
      <span className="line-clamp-2 text-sm leading-6 text-muted-foreground">
        {block.description}
      </span>
      {block.hasReact ? (
        <span className="mt-auto flex">
          <Badge variant="primary-light">React hooks</Badge>
        </span>
      ) : null}
    </SiteLink>
  );
}
