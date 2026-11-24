import type { ReactNode } from "react";

import { IntentLink } from "@/components/intent-link";
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { toAppHref } from "@/i18n/navigation";

export interface Kpi {
  readonly label: string;
  /** The formatted value; the band never formats it. */
  readonly value: string;
  readonly hint?: string;
  /** A page the figure opens, such as the list the number counts. */
  readonly href?: string;
  readonly icon?: ReactNode;
}

function KpiTile({ kpi }: { kpi: Kpi }) {
  const body = (
    <Card size="sm" className="h-full">
      <CardHeader>
        <CardDescription className="flex items-center gap-2">
          {kpi.icon}
          {kpi.label}
        </CardDescription>
        <CardTitle className="text-2xl font-semibold tracking-tight tabular-nums">
          {kpi.value}
        </CardTitle>
        {kpi.hint ? (
          <CardDescription className="text-xs">{kpi.hint}</CardDescription>
        ) : null}
      </CardHeader>
    </Card>
  );

  return kpi.href === undefined ? (
    body
  ) : (
    <IntentLink
      href={toAppHref(kpi.href)}
      className="rounded-xl transition-colors outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
    >
      {body}
    </IntentLink>
  );
}

/**
 * The KPI band of a hub or an overview: one Card per figure. Render it behind
 * its own `<Suspense>` with `KpiBandSkeleton`, because the figures are values
 * and the frame around them is not.
 */
export function KpiBand({ kpis }: { kpis: readonly Kpi[] }) {
  return (
    <section
      className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4"
      data-testid="kpi-band"
    >
      {kpis.map((kpi) => (
        <KpiTile key={kpi.label} kpi={kpi} />
      ))}
    </section>
  );
}

// skeleton: the loading state of KpiBand
export function KpiBandSkeleton({ count = 4 }: { count?: number }) {
  return (
    <section
      className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4"
      aria-busy="true"
    >
      {Array.from({ length: count }, (_, index) => (
        <Skeleton key={index} className="h-24 rounded-xl" />
      ))}
    </section>
  );
}
