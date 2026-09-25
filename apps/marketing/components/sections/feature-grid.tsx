import { ArrowUpRightIcon } from 'lucide-react';

import type { Feature } from '@/lib/home';

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
          ? 'grid gap-3 sm:grid-cols-2 lg:grid-cols-4'
          : 'grid gap-3 sm:grid-cols-2 lg:grid-cols-3'
      }
    >
      {items.map((item) => (
        <a
          key={item.title}
          href={item.href}
          className="group border-border bg-card hover:border-foreground/20 flex flex-col gap-2 rounded-xl border p-5 transition-colors"
        >
          <span className="flex items-center justify-between gap-2 text-sm font-semibold">
            {item.title}
            <ArrowUpRightIcon
              aria-hidden="true"
              className="text-muted-foreground group-hover:text-foreground size-4 shrink-0"
            />
          </span>
          <span className="text-muted-foreground text-sm leading-6">
            {item.body}
          </span>
        </a>
      ))}
    </div>
  );
}
