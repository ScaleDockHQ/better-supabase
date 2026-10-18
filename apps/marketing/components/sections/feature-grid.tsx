import { ArrowUpRightIcon } from "lucide-react";

import type { Feature } from "@/lib/home";

export function FeatureGrid({
  items,
  columns = 4,
}: {
  items: readonly Feature[];
  columns?: 3 | 4;
}) {
  return (
    <div
      className={
        columns === 4
          ? "grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4"
          : "grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3"
      }
    >
      {items.map((item) => (
        <a
          key={item.title}
          href={item.href}
          className="group flex flex-col gap-2 rounded-xl border border-border bg-card p-5 transition-colors hover:border-foreground/20"
        >
          <span className="flex items-center justify-between gap-2 text-sm font-semibold">
            {item.title}
            <ArrowUpRightIcon
              aria-hidden="true"
              className="size-4 shrink-0 text-muted-foreground group-hover:text-foreground"
            />
          </span>
          <span className="text-sm leading-6 text-muted-foreground">
            {item.body}
          </span>
        </a>
      ))}
    </div>
  );
}
