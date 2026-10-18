import { blocks } from "@/lib/blocks";
import { OgImage, ogSize } from "@/lib/og";

export const alt = "The better-supabase blocks";
export const size = ogSize;
export const contentType = "image/png";

export default function Image() {
  return OgImage({
    eyebrow: "Blocks",
    title: `${blocks.length} SQL blocks for Supabase`,
    description:
      "Tables, policies, triggers and functions you install with one command, each with a typed client.",
  });
}
