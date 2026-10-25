import type {
  ListOptions,
  PageOptions,
  SubscriptionLevel,
} from "./api-types.ts";
import type { NotificationAction, NotificationItem } from "./types.ts";

import { rowFields } from "../../core/block-fields.ts";
import { temporal } from "../../core/temporal-required.ts";
import { nullableInstant, nullableText } from "../shared.ts";

function objectOrNull(
  value: unknown,
): Readonly<Record<string, unknown>> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value))
    : null;
}

function actionsOf(value: unknown): readonly NotificationAction[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((entry: unknown) => {
    const action = objectOrNull(entry);
    const key = action?.["key"];
    const label = action?.["label"];

    if (typeof key !== "string" || typeof label !== "string") {
      return [];
    }

    const operation = action?.["operation"];
    const payload = objectOrNull(action?.["payload"]);

    return [
      {
        key,
        label,
        ...(typeof operation === "string" ? { operation } : {}),
        ...(payload === null ? {} : { payload }),
      },
    ];
  });
}

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
    actions: actionsOf(row["actions"]),
    priority: nullableText(row["priority"]),
    createdAt: nullableInstant(row["created_at"]) ?? temporal().Now.instant(),
    readAt: nullableInstant(row["read_at"]),
    resolvedAt: nullableInstant(row["resolved_at"]),
    resolution: objectOrNull(row["resolution"]),
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
