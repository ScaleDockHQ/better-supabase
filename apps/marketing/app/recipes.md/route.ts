import { markdownHeaders, recipesIndexMarkdown } from "@/lib/markdown";
import { availableRecipes, plannedRecipes } from "@/lib/recipes";
import { site } from "@/lib/site";

export function GET(): Response {
  return new Response(
    recipesIndexMarkdown(availableRecipes, plannedRecipes, site),
    { headers: markdownHeaders },
  );
}
