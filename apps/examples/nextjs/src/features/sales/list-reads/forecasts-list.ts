import type {
  EntityListMap,
  EntityPager,
  AppDb,
} from "@/lib/block-entity-page";

import { organizationPager } from "@/lib/block-entity-page";

import type { ForecastRow } from "../pipeline/pipeline-queries";

/** The forecasts list's URL names on the forecasts block's page. */
export const forecastsMap: EntityListMap = {
  sorts: {
    newest: { by: "takenAt", direction: "desc" },
    oldest: { by: "takenAt" },
    period: { by: "since", direction: "desc" },
  },
  filters: { f: "currency" },
  facets: { f: "currency" },
};

/**
 * The forecasts block's `page` and `facets`, as the snapshot rows the list
 * shows.
 */
export function forecastsPager(
  db: AppDb,
  organizationId: string,
): EntityPager<ForecastRow> {
  const pager = organizationPager(organizationId, {
    page: (options) => db.forecasts.page(options),
    facets: (options) => db.forecasts.facets(options),
  });

  return {
    facets: (options) => pager.facets(options),
    page: (options) =>
      pager
        .page(options)
        .map((page) => ({
          ...page,
          items: page.items.map((snapshot): ForecastRow => ({
            id: snapshot.id,
            since: snapshot.since.toString(),
            until: snapshot.until.toString(),
            currency: snapshot.currency,
            dealCount: snapshot.dealCount,
            commit: snapshot.totals.commit,
            bestCase: snapshot.totals.bestCase,
            won: snapshot.totals.won,
            target: snapshot.target ?? null,
            attainment: snapshot.totals.attainment ?? null,
            takenAt: snapshot.takenAt.toString(),
          })),
        })),
  };
}
