"use client";

import type { ReactNode } from "react";

import { SearchIcon, SearchXIcon } from "lucide-react";
import { useDeferredValue, useId, useState } from "react";

import type { BlockSummary } from "@/lib/block-filter";

import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Input } from "@/components/ui/input";
import { ALL_CATEGORIES, filterBlocks } from "@/lib/block-filter";

import { BlockTile } from "./block-tile";

/**
 * Search over every block. With an empty query it shows `children`, the
 * category sections rendered on the server; with a query it shows the matches.
 */
export function BlockSearch({
  blocks,
  children,
}: {
  blocks: readonly BlockSummary[];
  children: ReactNode;
}) {
  const [query, setQuery] = useState("");
  const deferredQuery = useDeferredValue(query);
  const searchId = useId();
  const searching = deferredQuery.trim() !== "";

  const matches = searching
    ? filterBlocks(blocks, ALL_CATEGORIES, deferredQuery)
    : [];

  return (
    <div className="flex flex-col gap-8">
      <div className="flex flex-col gap-2">
        <div className="relative max-w-md">
          <label htmlFor={searchId} className="sr-only">
            Search blocks
          </label>
          <SearchIcon
            aria-hidden="true"
            className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground"
          />
          <Input
            id={searchId}
            type="search"
            placeholder={`Search ${String(blocks.length)} blocks`}
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
            }}
            className="pl-8"
          />
        </div>
        <p className="text-xs text-muted-foreground" aria-live="polite">
          {searching
            ? `${String(matches.length)} of ${String(blocks.length)} blocks match`
            : null}
        </p>
      </div>
      {searching ? (
        matches.length === 0 ? (
          <Empty className="border border-dashed border-border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <SearchXIcon aria-hidden="true" />
              </EmptyMedia>
              <EmptyTitle>No block matches</EmptyTitle>
              <EmptyDescription>
                Try a table or feature name, such as invoices or comments.
              </EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Button
                variant="outline"
                size="sm"
                onClick={() => {
                  setQuery("");
                }}
              >
                Clear the search
              </Button>
            </EmptyContent>
          </Empty>
        ) : (
          <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
            {matches.map((block) => (
              <li key={block.name}>
                <BlockTile block={block} />
              </li>
            ))}
          </ul>
        )
      ) : (
        children
      )}
    </div>
  );
}
