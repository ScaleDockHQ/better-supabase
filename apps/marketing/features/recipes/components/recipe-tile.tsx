import type { Recipe } from "@/lib/recipes";

import { Badge } from "@/components/reui/badge";
import { SiteLink } from "@/components/site/site-link";
import { BlockIcon } from "@/features/blocks/components/block-icon";
import { recipeCategory, recipePath } from "@/lib/recipes";

import { RecipeCover } from "./recipe-cover";

/** A recipe in the `/recipes` grid: its cover, then what it builds and with which hook. */
export function RecipeTile({ recipe }: { recipe: Recipe }) {
  return (
    <SiteLink
      href={recipePath(recipe.slug)}
      className="group flex h-full flex-col overflow-hidden rounded-xl border border-border bg-card transition-colors outline-none hover:border-foreground/20 focus-visible:ring-3 focus-visible:ring-ring/50"
    >
      <RecipeCover recipe={recipe} className="border-b border-border" />
      <span className="flex flex-1 flex-col gap-2 p-4">
        <span className="flex items-center gap-2 text-sm font-medium">
          <BlockIcon
            name={recipe.block}
            category={recipeCategory(recipe)}
            size="sm"
          />
          {recipe.title}
        </span>
        <span className="line-clamp-2 text-sm leading-6 text-muted-foreground">
          {recipe.description}
        </span>
        <span className="mt-auto flex flex-wrap gap-1.5 pt-1">
          {recipe.hook ? (
            <Badge variant="outline" className="font-mono">
              {recipe.hook.name}
            </Badge>
          ) : null}
          <Badge variant="secondary">Web and native</Badge>
        </span>
      </span>
    </SiteLink>
  );
}
