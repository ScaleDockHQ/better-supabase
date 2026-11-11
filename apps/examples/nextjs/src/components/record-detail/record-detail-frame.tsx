import type { ReactNode } from "react";

/**
 * The frame of a record page: a head with an optional leading mark, the title,
 * a line under it, the status and the actions, then a main column and an aside.
 * Render the head from data the prefetch holds; the sections below it stream in
 * behind `AfterNavigation`.
 */
export function RecordDetailFrame({
  leading,
  title,
  description,
  status,
  actions,
  aside,
  children,
}: {
  leading?: ReactNode;
  title: string;
  description?: string | undefined;
  status?: ReactNode;
  actions?: ReactNode;
  aside?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className={`grid items-start gap-6 ${aside ? "lg:grid-cols-3" : ""}`}>
      <div className={`flex flex-col gap-6 ${aside ? "lg:col-span-2" : ""}`}>
        <header className="flex flex-wrap items-center gap-4">
          {leading}
          <div className="flex min-w-0 flex-1 flex-col gap-1">
            <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
            {description ? (
              <p className="text-sm text-muted-foreground">{description}</p>
            ) : null}
          </div>
          {status}
          {actions ? (
            <div className="flex items-center gap-2">{actions}</div>
          ) : null}
        </header>
        {children}
      </div>
      {aside ? <div className="flex flex-col gap-6">{aside}</div> : null}
    </div>
  );
}
