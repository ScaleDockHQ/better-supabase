import type { Metadata } from "next";

import type { RecipeGroup } from "@/lib/recipes";

import { Badge } from "@/components/reui/badge";
import { JsonLd } from "@/components/site/json-ld";
import { SiteLink } from "@/components/site/site-link";
import { categoryStyle } from "@/features/blocks/categories";
import { BlockIcon } from "@/features/blocks/components/block-icon";
import { CategoryIcon } from "@/features/blocks/components/category-icon";
import { PageHeader } from "@/features/catalog/components/page-header";
import { RecipeFilters } from "@/features/recipes/components/recipe-filters";
import { RecipeTile } from "@/features/recipes/components/recipe-tile";
import { blockPath } from "@/lib/blocks";
import {
  availableRecipes,
  recipeGroups,
  recipePath,
  recipeSummary,
} from "@/lib/recipes";
import { site } from "@/lib/site";
import { absoluteUrl, itemList } from "@/lib/structured-data";

export const metadata: Metadata = {
  title: "Recipes",
  description:
    "Build a notification bell, a command search or a settings screen from your own shadcn components and a block, on the web and in React Native.",
  alternates: { canonical: "/recipes" },
};

function RecipeGroupSection({ group }: { group: RecipeGroup }) {
  const headingId = `${categoryStyle(group.category).slug}-recipes`;
  const count = group.available.length + group.planned.length;

  return (
    <section
      id={categoryStyle(group.category).slug}
      aria-labelledby={headingId}
      className="flex scroll-mt-20 flex-col gap-4"
    >
      <h2
        id={headingId}
        className="flex items-center gap-3 text-xl font-semibold tracking-tight"
      >
        <CategoryIcon category={group.category} />
        {group.category}
        <span className="text-sm font-normal text-muted-foreground tabular-nums">
          {count}
        </span>
      </h2>
      {group.available.length === 0 ? null : (
        <ul className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {group.available.map((recipe) => (
            <li key={recipe.slug}>
              <RecipeTile recipe={recipeSummary(recipe)} />
            </li>
          ))}
        </ul>
      )}
      {group.planned.length === 0 ? null : (
        <ul
          aria-label={`Planned ${group.category} recipes`}
          className="flex flex-col divide-y divide-border rounded-xl border border-border"
        >
          {group.planned.map((recipe) => (
            <li
              key={recipe.slug}
              className="flex flex-col gap-2 px-4 py-3 sm:flex-row sm:items-center sm:gap-4"
            >
              <span className="flex items-center gap-3 text-sm font-medium sm:w-56">
                <BlockIcon
                  name={recipe.block}
                  category={group.category}
                  size="sm"
                />
                {recipe.title}
              </span>
              <span className="flex flex-1 flex-col gap-1">
                <span className="text-sm text-muted-foreground">
                  {recipe.description}
                </span>
                {recipe.missing ? (
                  <span className="text-xs text-muted-foreground">
                    Waits for: {recipe.missing}
                  </span>
                ) : null}
              </span>
              <span className="flex items-center gap-2">
                <Badge variant="outline">planned</Badge>
                <SiteLink
                  href={blockPath(recipe.block)}
                  className="font-mono text-xs text-muted-foreground transition-colors hover:text-foreground"
                >
                  {recipe.block}
                </SiteLink>
              </span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

export default function RecipesPage() {
  const groups = recipeGroups();

  return (
    <div className="flex flex-col gap-12">
      <PageHeader
        eyebrow="Recipes"
        title="Build the UI from your own components"
      >
        <p>
          better-supabase ships no UI components. Each recipe shows the shadcn
          components to add, the glue to install from the{" "}
          <SiteLink href="/docs/registry" className="text-foreground underline">
            @better-supabase registry
          </SiteLink>
          , and the web code, plus React Native where the recipe fits a phone.
          The code is copied from the example apps, so it typechecks and runs. A
          planned recipe says what it waits for; until then, build it from the
          block&apos;s TypeScript client in a server action or loader.
        </p>
      </PageHeader>

      <RecipeFilters
        recipes={availableRecipes.map(recipeSummary)}
        categories={groups
          .filter((group) => group.available.length > 0)
          .map((group) => group.category)}
      >
        <div className="flex flex-col gap-12">
          {groups.map((group) => (
            <RecipeGroupSection key={group.category} group={group} />
          ))}
        </div>
      </RecipeFilters>

      <JsonLd
        data={itemList(
          "better-supabase UI recipes",
          availableRecipes.map((recipe) => ({
            name: recipe.title,
            url: absoluteUrl(recipePath(recipe.slug), site.url),
          })),
        )}
      />
    </div>
  );
}
