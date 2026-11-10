import { availableRecipes, recipeSummary } from "@/lib/recipes";

/**
 * Every available recipe's summary, prerendered. The `/recipes` filters load it
 * on first use, so the page's document does not carry the list twice.
 */
export function GET(): Response {
  return Response.json(availableRecipes.map(recipeSummary));
}
