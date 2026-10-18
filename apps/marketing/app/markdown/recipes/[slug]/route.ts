import { markdownHeaders, recipeMarkdown } from "@/lib/markdown";
import { getRecipe, recipeStaticParams } from "@/lib/recipes";
import { site } from "@/lib/site";

export function generateStaticParams(): { slug: string }[] {
  return recipeStaticParams();
}

/** `/recipes/<slug>.md`, rewritten here by `proxy.ts`. */
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ slug: string }> },
): Promise<Response> {
  const { slug } = await params;
  const recipe = getRecipe(slug);

  if (!recipe) {
    return new Response("Not found\n", { status: 404 });
  }

  return new Response(recipeMarkdown(recipe, site), {
    headers: markdownHeaders,
  });
}
