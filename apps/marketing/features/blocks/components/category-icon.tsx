import { cn } from "@/lib/utils";

import { categoryStyle } from "../categories";

const SIZES = {
  sm: { tile: "size-5 rounded", icon: "size-3" },
  default: { tile: "size-8 rounded-md", icon: "size-4" },
  lg: { tile: "size-10 rounded-lg", icon: "size-5" },
} as const;

/** The category's icon on its soft hue. Decorative: the name sits next to it. */
export function CategoryIcon({
  category,
  size = "default",
}: {
  category: string;
  size?: keyof typeof SIZES;
}) {
  const style = categoryStyle(category);
  const Icon = style.icon;

  return (
    <span
      aria-hidden="true"
      className={cn(
        "flex shrink-0 items-center justify-center",
        SIZES[size].tile,
        style.soft,
        style.text,
      )}
    >
      <Icon className={SIZES[size].icon} />
    </span>
  );
}
