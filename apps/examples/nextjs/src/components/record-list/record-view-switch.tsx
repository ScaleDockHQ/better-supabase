import type { ReactNode } from "react";

import { getExtracted } from "next-intl/server";

import type { AppPathname } from "@/i18n/navigation";

import { buttonVariants } from "@/components/ui/button";
import { Link } from "@/i18n/navigation";

/** The view as a plain string, so a typed href does not multiply by the union. */
const viewName = (view: RecordView): string => view;

export type RecordView = "table" | "board" | "calendar" | "timeline";

/** The `view` named in a page's `searchParams`, or the first of `views`. */
export function activeView(
  raw: Readonly<Record<string, string | string[] | undefined>>,
  views: readonly RecordView[],
): RecordView {
  const value = Array.isArray(raw["view"]) ? raw["view"][0] : raw["view"];

  return views.find((view) => view === value) ?? views[0] ?? "table";
}

/**
 * The view switcher of an overview: links to `?view=table|board|calendar|
 * timeline` on the same page, so each view is a URL a prefetch can carry. The
 * first view is the page itself. Only the views the entity has are listed.
 */
export async function RecordViewSwitch({
  base,
  active,
  views,
  icons,
}: {
  base: AppPathname;
  active: RecordView;
  views: readonly RecordView[];
  icons?: Partial<Record<RecordView, ReactNode>>;
}) {
  const t = await getExtracted("recordList");

  const labels = {
    table: t("Table"),
    board: t("Board"),
    calendar: t("Calendar"),
    timeline: t("Timeline"),
  } as const satisfies Record<RecordView, string>;

  return (
    <nav aria-label={t("Views")} className="flex flex-wrap gap-1">
      {views.map((view, index) => (
        <Link
          key={view}
          href={index === 0 ? base : `${base}?view=${viewName(view)}`}
          aria-current={view === active ? "page" : undefined}
          className={buttonVariants({
            variant: view === active ? "secondary" : "ghost",
            size: "sm",
          })}
        >
          {icons?.[view]}
          {labels[view]}
        </Link>
      ))}
    </nav>
  );
}
