import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { Temporal } from "temporal-polyfill";

import { bsb } from "@/lib/supabase/server";

import { METRICS_TAG } from "./metrics-cache";

const DAYS = 90;
const DAY_MS = 86_400_000;

export interface MetricDetailData {
  readonly key: "customers";
  readonly value: number;
  readonly previous: number;
  readonly change: number | null;
  readonly weeks: readonly {
    readonly start: string;
    readonly value: number;
    readonly groups: Readonly<Record<string, number>>;
  }[];
  readonly groupNames: readonly string[];
}

/**
 * The customers metric over the last 90 days: the total against the 90 days
 * before, and one row per week split by customer status.
 */
export async function getCustomersMetric(): Promise<MetricDetailData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(METRICS_TAG);
  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const until = Temporal.Now.instant();

  const range = {
    from: until.subtract({ milliseconds: DAYS * DAY_MS }),
    until,
  };

  const [kpi, series] = await Promise.all([
    db.metrics
      .kpi({
        metric: "customers",
        range,
        options: { organizationId, compare: "previous" },
      })
      .orThrow(),
    db.metrics
      .series({
        metric: "customers",
        range,
        options: { organizationId, grain: "week", groupBy: "status" },
      })
      .orThrow(),
  ]);

  const names = new Set<string>();

  const weeks = series.points.map((point) => {
    const groups: Record<string, number> = {};

    for (const [name, value] of Object.entries(point.groups ?? {})) {
      names.add(name);
      groups[name] = value ?? 0;
    }

    return { start: point.bucket.toString(), value: point.value ?? 0, groups };
  });

  return {
    key: "customers",
    value: kpi.value ?? 0,
    previous: kpi.previous ?? 0,
    change: kpi.change ?? null,
    weeks,
    groupNames: [...names].toSorted(),
  };
}
