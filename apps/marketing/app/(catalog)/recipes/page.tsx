import type { Metadata } from "next";

import { Badge } from "@/components/reui/badge";
import { JsonLd } from "@/components/site/json-ld";
import { SiteLink } from "@/components/site/site-link";
import { CategoryIcon } from "@/features/blocks/components/category-icon";
import { PageHeader } from "@/features/catalog/components/page-header";
import { RecipeTile } from "@/features/recipes/components/recipe-tile";
import { blockPath, getBlock } from "@/lib/blocks";
import { availableRecipes, plannedRecipes, recipePath } from "@/lib/recipes";
import { site } from "@/lib/site";
import { absoluteUrl, itemList } from "@/lib/structured-data";

export const metadata: Metadata = {
  title: "Recipes",
  description:
    "Build a notification bell, a command search or an onboarding checklist from your own shadcn components and a block's hook, on the web and in React Native.",
  alternates: { canonical: "/recipes" },
};

export default function RecipesPage() {
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
          , and the web and React Native code side by side. Both call the same
          hook, and both are copied from the example apps, so they typecheck and
          run.
        </p>
      </PageHeader>

      <section aria-labelledby="available" className="flex flex-col gap-4">
        <h2 id="available" className="text-xl font-semibold tracking-tight">
          Available
          <span className="ml-2 text-sm font-normal text-muted-foreground tabular-nums">
            {availableRecipes.length}
          </span>
        </h2>
        <ul className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {availableRecipes.map((recipe) => (
            <li key={recipe.slug}>
              <RecipeTile recipe={recipe} />
            </li>
          ))}
        </ul>
      </section>

      {plannedRecipes.length === 0 ? null : (
        <section aria-labelledby="planned" className="flex flex-col gap-4">
          <div className="flex max-w-2xl flex-col gap-2">
            <h2 id="planned" className="text-xl font-semibold tracking-tight">
              Planned
            </h2>
            <p className="text-sm leading-6 text-muted-foreground">
              These wait for their block&apos;s hook. Until it ships, build them
              from the block&apos;s TypeScript client in a server action or
              loader.
            </p>
          </div>
          <ul className="flex flex-col divide-y divide-border rounded-xl border border-border">
            {plannedRecipes.map((recipe) => (
              <li
                key={recipe.slug}
                className="flex flex-col gap-2 px-4 py-3 sm:flex-row sm:items-center sm:gap-4"
              >
                <span className="flex items-center gap-3 text-sm font-medium sm:w-56">
                  <CategoryIcon
                    category={getBlock(recipe.block)?.category ?? "Foundation"}
                    size="sm"
                  />
                  {recipe.title}
                </span>
                <span className="flex-1 text-sm text-muted-foreground">
                  {recipe.description}
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
        </section>
      )}

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
