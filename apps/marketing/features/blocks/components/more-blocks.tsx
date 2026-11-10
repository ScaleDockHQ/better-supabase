"use client";

import { useState } from "react";

import { Button } from "@/components/ui/button";
import { IndexPending } from "@/features/catalog/components/index-pending";
import { useCatalogIndex } from "@/features/catalog/use-catalog-index";
import { blockSummariesSchema } from "@/lib/block-filter";

import { BlockTile } from "./block-tile";

/**
 * The rest of a category's blocks. The page renders the first few tiles and
 * this button loads the others from `/blocks/index.json`, so the document stays
 * under 512 KB (Vercel warns above it). Every block is also a link in the
 * sidebar, which is in the document.
 */
export function MoreBlocks({
  category,
  shown,
  total,
}: {
  category: string;
  shown: number;
  total: number;
}) {
  const [open, setOpen] = useState(false);

  const { index, load } = useCatalogIndex(
    "/blocks/index.json",
    blockSummariesSchema,
  );

  const rest =
    index.status === "ready"
      ? index.items.filter((block) => block.category === category).slice(shown)
      : [];

  return (
    <div className="flex flex-col gap-3">
      {open ? (
        index.status === "ready" ? (
          <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
            {rest.map((block) => (
              <li key={block.name}>
                <BlockTile block={block} />
              </li>
            ))}
          </ul>
        ) : (
          <IndexPending failed={index.status === "error"} onRetry={load} />
        )
      ) : null}
      <div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => {
            load();
            setOpen((current) => !current);
          }}
        >
          {open
            ? "Show fewer blocks"
            : `Show the other ${String(total - shown)} blocks`}
        </Button>
      </div>
    </div>
  );
}
