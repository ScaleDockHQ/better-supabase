import { OgImage, ogSize } from "@/lib/og";
import { availableRecipes } from "@/lib/recipes";

export const alt = "The better-supabase recipes";
export const size = ogSize;
export const contentType = "image/png";

export default function Image() {
  return OgImage({
    eyebrow: "Recipes",
    title: `${availableRecipes.length} UI recipes for the blocks`,
    description:
      "shadcn components and the block's React hooks, for Next.js and Expo.",
  });
}
