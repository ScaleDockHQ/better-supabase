import { ArrowRightIcon } from "lucide-react";

import { Section } from "@/components/sections/section";
import { LinkButton } from "@/components/site/link-button";
import { RecipeTile } from "@/features/recipes/components/recipe-tile";
import { availableRecipes, recipeSummary } from "@/lib/recipes";

const SHOWN = 4;

/** The first recipes, so the home page shows the UI side of the blocks. */
export function RecipesStrip() {
  return (
    <Section
      id="recipes"
      eyebrow="Recipes"
      title="Build the UI from your own components"
      description="Each recipe pairs a block with shadcn components on the web, and with React Native where it fits a phone, copied from example apps that typecheck and run."
    >
      <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {availableRecipes.slice(0, SHOWN).map((recipe) => (
          <li key={recipe.slug}>
            <RecipeTile recipe={recipeSummary(recipe)} />
          </li>
        ))}
      </ul>
      <div className="pt-8">
        <LinkButton variant="outline" href="/recipes">
          All {availableRecipes.length} recipes
          <ArrowRightIcon aria-hidden="true" />
        </LinkButton>
      </div>
    </Section>
  );
}
