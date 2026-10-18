import type { BlockGroup } from "@/lib/blocks";

import { cn } from "@/lib/utils";

import { categoryStyle } from "../categories";
import { BlockPreview } from "./block-preview";
import { BlockTile } from "./block-tile";
import { CategoryIcon } from "./category-icon";

/** A category on `/blocks`: its scene and summary, then a tile per block. */
export function CategorySection({ group }: { group: BlockGroup }) {
  const style = categoryStyle(group.category);
  const headingId = `${style.slug}-heading`;
  const count = group.blocks.length;

  return (
    <section
      id={style.slug}
      aria-labelledby={headingId}
      className="flex scroll-mt-20 flex-col gap-4"
    >
      <div
        className={cn(
          "grid grid-cols-1 overflow-hidden rounded-xl border sm:grid-cols-[1fr_minmax(0,18rem)]",
          style.ring,
        )}
      >
        <div className="flex flex-col justify-center gap-3 p-6">
          <CategoryIcon category={group.category} size="lg" />
          <h2 id={headingId} className="text-2xl font-semibold tracking-tight">
            {group.category}
          </h2>
          <p className="text-sm leading-6 text-pretty text-muted-foreground">
            {style.summary}
          </p>
          <p className={cn("text-xs font-medium", style.text)}>
            {count === 1 ? "1 block" : `${String(count)} blocks`}
          </p>
        </div>
        <BlockPreview
          category={group.category}
          className="hidden sm:flex sm:aspect-auto"
        />
      </div>
      <ul className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {group.blocks.map((block) => (
          <li key={block.name}>
            <BlockTile block={block} />
          </li>
        ))}
      </ul>
    </section>
  );
}
