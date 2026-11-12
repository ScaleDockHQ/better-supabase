import { getExtracted } from "next-intl/server";

import type { AppPathname } from "@/i18n/navigation";

import { buttonVariants } from "@/components/ui/button";
import { Link } from "@/i18n/navigation";

// skeleton: renders from props, so nothing of its own suspends
/**
 * Links between the tabs of one page. The first tab is the page itself; the
 * others add `?tab=<value>`, so each tab is a URL a prefetch and a link can
 * carry. The page reads `tab` and renders the matching section.
 */
export async function RecordDetailTabs({
  base,
  active,
  tabs,
}: {
  base: AppPathname;
  active: string;
  tabs: readonly { readonly value: string; readonly label: string }[];
}) {
  const t = await getExtracted("recordDetail");

  return (
    <nav aria-label={t("Tabs")} className="flex flex-wrap gap-2">
      {tabs.map((tab, index) => (
        <Link
          key={tab.value}
          href={index === 0 ? base : `${base}?tab=${tab.value}`}
          aria-current={tab.value === active ? "page" : undefined}
          className={buttonVariants({
            variant: tab.value === active ? "secondary" : "ghost",
            size: "sm",
          })}
        >
          {tab.label}
        </Link>
      ))}
    </nav>
  );
}

/** The tab named in a page's `searchParams`, or the first one. */
export function activeTab(
  raw: Readonly<Record<string, string | string[] | undefined>>,
  values: readonly string[],
): string {
  const value = Array.isArray(raw["tab"]) ? raw["tab"][0] : raw["tab"];

  return value !== undefined && values.includes(value)
    ? value
    : (values[0] ?? "");
}
