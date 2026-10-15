"use client";

import { SearchIcon } from "lucide-react";
import { useId, useState } from "react";

import { Badge } from "@/components/reui/badge";
import { SiteLink } from "@/components/site/site-link";
import { Input } from "@/components/ui/input";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  ALL_CATEGORIES,
  type BlockSummary,
  filterBlocks,
} from "@/lib/block-filter";

interface BlocksBrowserProps {
  readonly blocks: readonly BlockSummary[];
  readonly categories: readonly string[];
}

export function BlocksBrowser({ blocks, categories }: BlocksBrowserProps) {
  const [category, setCategory] = useState(ALL_CATEGORIES);
  const [query, setQuery] = useState("");
  const searchId = useId();
  const visible = filterBlocks(blocks, category, query);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-4">
        <div className="relative max-w-sm">
          <label htmlFor={searchId} className="sr-only">
            Search blocks
          </label>
          <SearchIcon
            aria-hidden="true"
            className="text-muted-foreground pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2"
          />
          <Input
            id={searchId}
            type="search"
            placeholder="Search blocks"
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
            }}
            className="pl-8"
          />
        </div>
        <Tabs value={category} onValueChange={setCategory}>
          <TabsList
            aria-label="Categories"
            className="flex-wrap justify-start group-data-horizontal/tabs:h-auto"
          >
            {[ALL_CATEGORIES, ...categories].map((name) => (
              <TabsTrigger key={name} value={name} className="flex-none">
                {name}
              </TabsTrigger>
            ))}
          </TabsList>
        </Tabs>
      </div>
      <p className="text-muted-foreground text-sm" aria-live="polite">
        {visible.length === 1 ? "1 block" : `${String(visible.length)} blocks`}
      </p>
      <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {visible.map((block) => (
          <li key={block.name}>
            <SiteLink
              href={`/blocks/${block.name}`}
              className="border-border bg-card hover:bg-muted/50 focus-visible:ring-ring/50 flex h-full flex-col gap-3 rounded-xl border p-5 transition-colors outline-none focus-visible:ring-3"
            >
              <span className="flex flex-col gap-1">
                <span className="text-sm font-semibold">{block.title}</span>
                <span className="text-muted-foreground font-mono text-xs">
                  {block.name}
                </span>
              </span>
              <span className="text-muted-foreground line-clamp-3 text-sm leading-6">
                {block.description}
              </span>
              <span className="mt-auto flex flex-wrap gap-1.5">
                <Badge variant="secondary">{block.category}</Badge>
                {block.hasReact ? (
                  <Badge variant="primary-light">React</Badge>
                ) : null}
                {block.requires.map((name) => (
                  <Badge key={name} variant="outline">
                    needs {name}
                  </Badge>
                ))}
              </span>
            </SiteLink>
          </li>
        ))}
      </ul>
      {visible.length === 0 ? (
        <p className="text-muted-foreground text-sm">
          No block matches. Clear the search or pick another category.
        </p>
      ) : null}
    </div>
  );
}
