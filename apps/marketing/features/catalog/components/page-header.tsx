import type { ReactNode } from "react";

/** The heading block every catalog page starts with. */
export function PageHeader({
  eyebrow,
  title,
  children,
  actions,
}: {
  eyebrow: ReactNode;
  title: string;
  children?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <header className="flex flex-col gap-3">
      <div className="text-xs font-semibold tracking-wide text-brand uppercase">
        {eyebrow}
      </div>
      <h1 className="text-3xl font-semibold tracking-tight text-balance">
        {title}
      </h1>
      {children ? (
        <div className="max-w-2xl text-base leading-7 text-pretty text-muted-foreground">
          {children}
        </div>
      ) : null}
      {actions ? (
        <div className="flex flex-wrap items-center gap-2 pt-1">{actions}</div>
      ) : null}
    </header>
  );
}
