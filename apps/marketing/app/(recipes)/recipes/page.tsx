import type { Metadata } from "next";

import { Suspense } from "react";

import type { RecipeGroup } from "@/lib/recipes";

import { JsonLd } from "@/components/site/json-ld";
import { SiteLink } from "@/components/site/site-link";
import { categoryStyle } from "@/features/blocks/categories";
import { CategoryIcon } from "@/features/blocks/components/category-icon";
import { PageHeader } from "@/features/catalog/components/page-header";
import { MoreRecipes } from "@/features/recipes/components/more-recipes";
import { RecipeFilters } from "@/features/recipes/components/recipe-filters";
import { RecipeTile } from "@/features/recipes/components/recipe-tile";
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

/**
 * How many recipes of a category get a tile. The rest are links in a collapsed
 * list, so the page's document stays under 512 KB (Vercel warns above it).
 */
const TILES_PER_CATEGORY = 1;

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
          {group.available.slice(0, TILES_PER_CATEGORY).map((recipe) => (
            <li key={recipe.slug}>
              <RecipeTile recipe={recipeSummary(recipe)} />
            </li>
          ))}
        </ul>
      )}
      {group.available.length > TILES_PER_CATEGORY ? (
        <MoreRecipes
          category={group.category}
          shown={TILES_PER_CATEGORY}
          total={group.available.length}
        />
      ) : null}
      {group.planned.length === 0 ? null : (
        <p className="text-sm leading-6 text-muted-foreground">
          <span className="font-medium text-foreground">Planned:</span>{" "}
          {group.planned.map((recipe) => recipe.title).join(", ")}. Each waits
          for a feature of its block; the block&apos;s page says which.
        </p>
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
        categories={groups
          .filter((group) => group.available.length > 0)
          .map((group) => group.category)}
      >
        <div className="flex flex-col gap-12">
          {groups.map((group, index) =>
            // The first group is above the fold; each later one streams in its own boundary.
            index === 0 ? (
              <RecipeGroupSection key={group.category} group={group} />
            ) : (
              <Suspense key={group.category} fallback={null}>
                <RecipeGroupSection group={group} />
              </Suspense>
            ),
          )}
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
