import type { ReactNode } from "react";

import type { Kpi } from "@/components/record-list/kpi-band";
import type { AppDb } from "@/lib/block-entity-page";

import { KpiBand } from "@/components/record-list/kpi-band";
import { overviewContext } from "@/features/sales/components/overview-support";

type Writable<T> = { -readonly [K in keyof T]: T[K] };

/** One figure of an overview: a label and the count behind it. */
export interface CountSource {
  readonly label: string;
  readonly hint?: string;
  readonly href?: string;
  readonly icon?: ReactNode;
  readonly read: (db: AppDb) => PromiseLike<number>;
}

/**
 * The KPI band of an overview: each source is one count read in parallel, so
 * the band costs as many reads as it shows figures. Render it behind its own
 * `<Suspense>` with `KpiBandSkeleton`, because the figures are values.
 */
// skeleton: the page's Suspense fallback is KpiBandSkeleton
export async function CountKpis({
  sources,
}: {
  sources: readonly CountSource[];
}) {
  const context = await overviewContext();

  if (context === null) {
    return null;
  }

  const counts = await Promise.all(
    sources.map((source) => source.read(context.db)),
  );

  const kpis = sources.map((source, index) => {
    const kpi: Writable<Kpi> = {
      label: source.label,
      value: String(counts[index] ?? 0),
    };

    if (source.hint !== undefined) {
      kpi.hint = source.hint;
    }

    if (source.href !== undefined) {
      kpi.href = source.href;
    }

    if (source.icon !== undefined) {
      kpi.icon = source.icon;
    }

    return kpi;
  });

  return <KpiBand kpis={kpis} />;
}
