import type { Metadata } from "next";

import { Badge } from "@/components/reui/badge";
import { SiteLink } from "@/components/site/site-link";
import { availableRecipes, plannedRecipes, recipePath } from "@/lib/recipes";

export const metadata: Metadata = {
  title: "Recipes",
  description:
    "Build a notification bell, a command search or an onboarding checklist from your own shadcn components and a block's hook, on the web and in React Native.",
};

export default function RecipesPage() {
  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-12 px-6 py-16 md:px-8">
      <div className="flex max-w-2xl flex-col gap-3">
        <p className="text-brand text-xs font-semibold tracking-wide uppercase">
          Recipes
        </p>
        <h1 className="text-3xl font-semibold tracking-tight">
          Build the UI from your own components
        </h1>
        <p className="text-muted-foreground text-base leading-7 text-pretty">
          better-supabase ships no UI components. Each recipe shows the shadcn
          components to add, the glue to install from the{" "}
          <SiteLink href="/docs/registry" className="text-foreground underline">
            @better-supabase registry
          </SiteLink>
          , and the web and React Native code side by side. Both call the same
          hook, and both are copied from the example apps, so they typecheck and
          run.
        </p>
      </div>

      <section aria-labelledby="available" className="flex flex-col gap-4">
        <h2 id="available" className="text-xl font-semibold tracking-tight">
          Available
        </h2>
        <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {availableRecipes.map((recipe) => (
            <li key={recipe.slug}>
              <SiteLink
                href={recipePath(recipe.slug)}
                className="border-border bg-card hover:bg-muted/50 focus-visible:ring-ring/50 flex h-full flex-col gap-3 rounded-xl border p-5 transition-colors outline-none focus-visible:ring-3"
              >
                <span className="text-sm font-semibold">{recipe.title}</span>
                <span className="text-muted-foreground line-clamp-3 text-sm leading-6">
                  {recipe.description}
                </span>
                <span className="mt-auto flex flex-wrap gap-1.5">
                  <Badge variant="secondary">{recipe.block}</Badge>
                  <Badge variant="outline" className="font-mono">
                    {recipe.hook.name}
                  </Badge>
                  <Badge variant="primary-light">Web and native</Badge>
                </span>
              </SiteLink>
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="planned" className="flex flex-col gap-4">
        <div className="flex max-w-2xl flex-col gap-2">
          <h2 id="planned" className="text-xl font-semibold tracking-tight">
            Planned
          </h2>
          <p className="text-muted-foreground text-sm leading-6">
            These wait for their block&apos;s hook. Until it ships, build them
            from the block&apos;s TypeScript client in a server action or
            loader.
          </p>
        </div>
        <ul className="border-border divide-border divide-y rounded-xl border">
          {plannedRecipes.map((recipe) => (
            <li
              key={recipe.slug}
              className="flex flex-col gap-1 px-4 py-3 sm:flex-row sm:items-center sm:gap-4"
            >
              <span className="text-sm font-medium sm:w-48">
                {recipe.title}
              </span>
              <span className="text-muted-foreground flex-1 text-sm">
                {recipe.description}
              </span>
              <SiteLink
                href={`/blocks/${recipe.block}`}
                className="text-muted-foreground hover:text-foreground font-mono text-xs"
              >
                {recipe.block}
              </SiteLink>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
