import Image from "next/image";

import type { RecipeSummary } from "@/lib/recipe-filter";

import {
  BlockPreview,
  PreviewSurface,
} from "@/features/blocks/components/block-preview";
import { cn } from "@/lib/utils";

/** Below this height-to-width ratio a screenshot is a strip that reads as a line in a tile. */
const MIN_TILE_RATIO = 0.25;

/**
 * The recipe's screenshot from the Next.js example on its primary block's
 * category surface, or the category scene until a usable screenshot exists.
 */
export function RecipeCover({
  recipe,
  size = "default",
  preload = false,
  className,
}: {
  recipe: Pick<RecipeSummary, "title" | "category" | "screenshot">;
  size?: "default" | "lg";
  preload?: boolean;
  className?: string;
}) {
  const { category } = recipe;
  const shot = recipe.screenshot;

  const usable =
    shot !== null &&
    (size === "lg" || shot.height / shot.width >= MIN_TILE_RATIO);

  if (!usable) {
    return (
      <BlockPreview category={category} size={size} className={className} />
    );
  }

  const strip = shot.height / shot.width < MIN_TILE_RATIO;

  return (
    <PreviewSurface
      category={category}
      size={size}
      className={cn(strip && "aspect-auto", className)}
    >
      <Image
        src={shot.src}
        width={shot.width}
        height={shot.height}
        alt={
          size === "lg"
            ? `${recipe.title} in the Next.js example, signed in as the seed user`
            : ""
        }
        preload={preload}
        sizes={
          size === "lg"
            ? "(min-width: 1280px) 900px, 100vw"
            : "(min-width: 1280px) 300px, (min-width: 640px) 50vw, 100vw"
        }
        className="relative max-h-full w-auto rounded-md border border-border object-contain shadow-xs"
      />
    </PreviewSurface>
  );
}
