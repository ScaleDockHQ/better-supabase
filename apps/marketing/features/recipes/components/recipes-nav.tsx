import { LayoutTemplateIcon } from "lucide-react";

import { categoryStyle } from "@/features/blocks/categories";
import { BlockGlyph } from "@/features/blocks/components/block-icon";
import { CategoryIcon } from "@/features/blocks/components/category-icon";
import { CatalogLink } from "@/features/catalog/components/catalog-link";
import { recipeGroups, recipePath } from "@/lib/recipes";

/**
 * The `/recipes` sidebar: the overview, then the recipes under their block's
 * category. Planned recipes have no page yet, so they are listed as text.
 */
export function RecipesNav() {
  return (
    <nav aria-label="Recipes" className="flex flex-col gap-6 text-sm">
      <CatalogLink href="/recipes">
        <LayoutTemplateIcon aria-hidden="true" className="size-4" />
        All recipes
      </CatalogLink>
      {recipeGroups().map((group) => {
        const headingId = `nav-recipes-${categoryStyle(group.category).slug}`;

        return (
          <section
            key={group.category}
            aria-labelledby={headingId}
            className="flex flex-col gap-1"
          >
            <h2
              id={headingId}
              className="flex items-center gap-2 px-2 text-xs font-medium text-foreground"
            >
              <CategoryIcon category={group.category} size="sm" />
              {group.category}
              <span className="ml-auto text-muted-foreground tabular-nums">
                {group.available.length + group.planned.length}
              </span>
            </h2>
            <ul className="ml-4.5 flex flex-col gap-0.5 border-l border-border pl-2">
              {group.available.map((recipe) => (
                <li key={recipe.slug}>
                  <CatalogLink
                    href={recipePath(recipe.slug)}
                    className="min-h-7"
                  >
                    <BlockGlyph name={recipe.block} category={group.category} />
                    <span className="truncate">{recipe.title}</span>
                  </CatalogLink>
                </li>
              ))}
              {group.planned.map((recipe) => (
                <li
                  key={recipe.slug}
                  className="flex min-h-7 items-center gap-2 px-2 text-muted-foreground"
                >
                  <BlockGlyph name={recipe.block} category={group.category} />
                  <span className="truncate">{recipe.title}</span>
                  <span className="ml-auto text-xs">planned</span>
                </li>
              ))}
            </ul>
          </section>
        );
      })}
    </nav>
  );
}
