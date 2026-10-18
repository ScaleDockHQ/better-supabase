import { OgImage, ogSize } from "@/lib/og";

export const alt = "Create a better-supabase app";
export const size = ogSize;
export const contentType = "image/png";

export default function Image() {
  return OgImage({
    eyebrow: "Create",
    title: "Start an app from a preset",
    description:
      "Pick a preset, a framework and the blocks, then copy one command that scaffolds the project.",
  });
}
