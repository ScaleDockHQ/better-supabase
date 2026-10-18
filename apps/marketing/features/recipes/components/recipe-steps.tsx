import type { ReactNode } from "react";

/** The numbered steps of a recipe, joined by a line down the left. */
export function RecipeSteps({ children }: { children: ReactNode }) {
  return <ol className="flex flex-col">{children}</ol>;
}

export function RecipeStep({
  number,
  title,
  children,
}: {
  number: number;
  title: string;
  children: ReactNode;
}) {
  const id = `step-${String(number)}`;

  return (
    <li className="group relative flex gap-4 pb-12 last:pb-0">
      <span
        aria-hidden="true"
        className="absolute top-8 bottom-0 left-3.5 w-px bg-border group-last:hidden"
      />
      <span
        aria-hidden="true"
        className="flex size-7 shrink-0 items-center justify-center rounded-full border border-border bg-background text-xs font-semibold tabular-nums"
      >
        {number}
      </span>
      <section
        aria-labelledby={id}
        className="flex min-w-0 flex-1 scroll-mt-20 flex-col gap-4 pt-0.5"
      >
        <h2 id={id} className="text-xl font-semibold tracking-tight">
          {title}
        </h2>
        {children}
      </section>
    </li>
  );
}
