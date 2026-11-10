"use client";

import { useState } from "react";

import { Button } from "@/components/ui/button";
import { IndexPending } from "@/features/catalog/components/index-pending";
import { useCatalogIndex } from "@/features/catalog/use-catalog-index";
import { recipeSummariesSchema } from "@/lib/recipe-filter";

import { RecipeTile } from "./recipe-tile";

/**
 * The rest of a category's recipes. The page renders the first few tiles and
 * this button loads the others from `/recipes/index.json`, so the document
 * stays under 512 KB (Vercel warns above it). Every recipe is also a link in
 * the sidebar, which is in the document.
 */
export function MoreRecipes({
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
    "/recipes/index.json",
    recipeSummariesSchema,
  );

  const rest =
    index.status === "ready"
      ? index.items
          .filter((recipe) => recipe.category === category)
          .slice(shown)
      : [];

  return (
    <div className="flex flex-col gap-4">
      {open ? (
        index.status === "ready" ? (
          <ul className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
            {rest.map((recipe) => (
              <li key={recipe.slug}>
                <RecipeTile recipe={recipe} />
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
            ? "Show fewer recipes"
            : `Show the other ${String(total - shown)} recipes`}
        </Button>
      </div>
    </div>
  );
}
