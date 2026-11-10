import type { AuditListOptions } from "better-supabase/blocks/audit";
import type * as v from "valibot";

import type { auditExportSchema } from "@/features/jobs/jobs-server";

/** The most rows one request streams; a larger range runs as an export job. */
export const EXPORT_ROW_LIMIT = 100_000;

/** The private bucket the data lifecycle exports use. */
export const EXPORT_BUCKET = "data-exports";

/** How long a download link from the export route lives. */
export const EXPORT_LINK_SECONDS = 15 * 60;

const DEFAULT_WINDOW_HOURS = 30 * 24;

export type AuditExportInput = v.InferOutput<typeof auditExportSchema>;

/** The text form of the page's filters, as the URL carries them. */
export type AuditExportParams = Pick<
  AuditExportInput,
  "actor" | "from" | "q" | "to" | "type"
>;

type Filters = { -readonly [K in keyof AuditListOptions]: AuditListOptions[K] };

/** The object an export job writes: one folder per organization. */
export const exportPath = (tenant: string, job: string): string =>
  `audit/${tenant}/${job}.csv`;

export function paramsOf(search: URLSearchParams): AuditExportParams {
  return {
    from: search.get("from"),
    to: search.get("to"),
    actor: search.get("actor"),
    type: search.get("type"),
    q: search.get("q"),
  };
}

/** The same filters and window as the page: the last 30 days without `from`. */
export function filtersOf(
  organizationId: string,
  params: AuditExportParams,
): Filters {
  const filters: Filters = {
    organizationId,
    since: params.from
      ? Temporal.Instant.from(params.from)
      : Temporal.Now.instant().subtract({ hours: DEFAULT_WINDOW_HOURS }),
  };

  if (params.to) {
    filters.until = Temporal.Instant.from(params.to);
  }

  if (params.actor) {
    filters.actorId = params.actor;
  }

  if (params.type) {
    filters.eventType = params.type;
  }

  if (params.q) {
    filters.search = params.q;
  }

  return filters;
}
