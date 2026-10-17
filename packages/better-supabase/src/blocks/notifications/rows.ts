import type {
  ListOptions,
  PageOptions,
  SubscriptionLevel,
} from "./api-types.ts";
import type { NotificationItem } from "./types.ts";

import { rowFields } from "../../core/block-fields.ts";
import { temporal } from "../../core/temporal-required.ts";
import { nullableInstant, nullableText } from "../shared.ts";

export function toItem(row: Record<string, unknown>): NotificationItem {
  const type = nullableText(row["subject_type"]);
  const id = nullableText(row["subject_id"]);
  const label = nullableText(row["subject_label"]);
  return {
    id: String(row["id"]),
    eventId: String(row["event_id"]),
    type: String(row["type"]),
    data: row["data"] ?? {},
    tenant: nullableText(row["tenant"]),
    actorId: nullableText(row["actor_id"]),
    subject:
      type === null || id === null
        ? null
        : { type, id, ...(label === null ? {} : { label }) },
    summary: nullableText(row["summary"]),
    actionPath: nullableText(row["action_path"]),
    priority: nullableText(row["priority"]),
    createdAt: nullableInstant(row["created_at"]) ?? temporal().Now.instant(),
    readAt: nullableInstant(row["read_at"]),
    resolvedAt: nullableInstant(row["resolved_at"]),
    fields: rowFields(row["fields"]),
  };
}

export function cursorOf(before: ListOptions["cursor"]): {
  readonly before: string | null;
  readonly before_id: string | null;
} {
  if (before === undefined) {
    return { before: null, before_id: null };
  }
  if ("epochNanoseconds" in before) {
    return { before: before.toString(), before_id: null };
  }
  return { before: before.createdAt.toString(), before_id: before.id };
}

export function publicObjectUrl(
  url: string,
  bucket: string,
  path: string,
): string {
  const object = path
    .replace(/^\/+/, "")
    .split("/")
    .map(encodeURIComponent)
    .join("/");
  return `${url.replace(/\/+$/, "")}/storage/v1/object/public/${encodeURIComponent(bucket)}/${object}`;
}

export function filtersOf(filters: PageOptions): Record<string, unknown> {
  return {
    tenant: filters.tenant ?? null,
    status: filters.status ?? "all",
    read: filters.read ?? null,
    resolved: filters.resolved ?? null,
    dismissed: filters.dismissed === undefined ? false : filters.dismissed,
    types: filters.types ?? null,
    subject_types: filters.subjectTypes ?? null,
    search: filters.search ?? null,
  };
}

export const LEVELS: readonly SubscriptionLevel[] = [
  "participating",
  "all",
  "ignore",
];
