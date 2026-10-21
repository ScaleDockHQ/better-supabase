import type { Metadata } from "next";

import { Suspense } from "react";

import { DetailSkeleton } from "@/features/catalog/components/detail-skeleton";
import { RecipeDetail } from "@/features/recipes/components/recipe-detail";
import { getRecipe, recipePath, recipeStaticParams } from "@/lib/recipes";

interface RecipePageProps {
  readonly params: Promise<{ slug: string }>;
}

export function generateStaticParams(): { slug: string }[] {
  return recipeStaticParams();
}

export async function generateMetadata({
  params,
}: RecipePageProps): Promise<Metadata> {
  const recipe = getRecipe((await params).slug);

  if (!recipe) {
    return {};
  }

  const path = recipePath(recipe.slug);

  return {
    title: `${recipe.title} recipe`,
    description: recipe.description,
    alternates: { canonical: path, types: { "text/markdown": `${path}.md` } },
    openGraph: { url: path },
  };
}

export default function RecipePage({ params }: RecipePageProps) {
  return (
    <Suspense fallback={<DetailSkeleton />}>
      <RecipeDetail params={params} />
    </Suspense>
  );
}
