import { ClockIcon, FileTextIcon, HistoryIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";

import { KpiBand, KpiBandSkeleton } from "@/components/record-list/kpi-band";

import { getDocuments } from "../documents-queries";

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

export function DocumentsOverviewSkeleton() {
  return <KpiBandSkeleton />;
}

/**
 * The figures above the document list: how many documents there are, how many
 * changed in the last seven days and when the latest edit happened. Read from
 * the same cached list the table uses, so it adds no call.
 */
// skeleton: the page's Suspense fallback is DocumentsOverviewSkeleton
export async function DocumentsOverview() {
  const [t, format, state] = await Promise.all([
    getExtracted("documents"),
    getFormatter(),
    getDocuments(),
  ]);

  if (state.kind !== "ok") {
    return null;
  }

  const stamps = state.data.map((row) => new Date(row.updatedAt).getTime());
  const latest = stamps.reduce((a, b) => Math.max(a, b), 0);
  const recent = stamps.filter((stamp) => latest - stamp < WEEK_MS).length;

  return (
    <KpiBand
      kpis={[
        {
          label: t("Documents"),
          value: String(state.data.length),
          hint: t("One notes document per customer"),
          icon: <FileTextIcon className="size-4" />,
        },
        {
          label: t("Edited in the last week"),
          value: String(recent),
          hint: t("Counted back from the latest edit"),
          icon: <HistoryIcon className="size-4" />,
        },
        {
          label: t("Latest edit"),
          value:
            latest === 0
              ? "–"
              : format.dateTime(new Date(latest), { dateStyle: "medium" }),
          hint: t("Of any document"),
          icon: <ClockIcon className="size-4" />,
        },
      ]}
    />
  );
}
