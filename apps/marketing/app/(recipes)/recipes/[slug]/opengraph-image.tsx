import { OgImage, ogSize } from "@/lib/og";
import { getRecipe, recipeStaticParams } from "@/lib/recipes";

export const alt = "A better-supabase recipe";
export const size = ogSize;
export const contentType = "image/png";

export function generateStaticParams(): { slug: string }[] {
  return recipeStaticParams();
}

export default async function Image({
  params,
}: {
  readonly params: Promise<{ slug: string }>;
}) {
  const recipe = getRecipe((await params).slug);

  return OgImage({
    eyebrow: recipe ? `Recipe / ${recipe.block}` : "Recipe",
    title: recipe?.title ?? "Recipe",
    description: recipe?.description ?? "",
  });
}
