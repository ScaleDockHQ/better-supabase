import { createElement } from "react";

import { cn } from "@/lib/utils";

import { blockIcon } from "../block-icons";
import { categoryStyle } from "../categories";

const SIZES = {
  xs: { tile: "size-5 rounded", icon: "size-3" },
  sm: { tile: "size-6 rounded-md", icon: "size-3.5" },
  default: { tile: "size-8 rounded-md", icon: "size-4" },
  lg: { tile: "size-10 rounded-lg", icon: "size-5" },
} as const;

/**
 * The block's own icon on its category's soft hue, so the shape names the
 * block and the color names the category. Decorative: the title sits next to it.
 */
export function BlockIcon({
  name,
  category,
  size = "default",
  className,
}: {
  name: string;
  category: string;
  size?: keyof typeof SIZES;
  className?: string;
}) {
  const style = categoryStyle(category);

  return (
    <span
      aria-hidden="true"
      className={cn(
        "flex shrink-0 items-center justify-center",
        SIZES[size].tile,
        style.soft,
        style.text,
        className,
      )}
    >
      {createElement(blockIcon(name, category), {
        className: SIZES[size].icon,
      })}
    </span>
  );
}
