import type { BlockSqlContext } from "../context.ts";

import { extraFieldsJson } from "../shared.ts";
import { calendarFeatures, recurrenceSql } from "./calendar-features.ts";

export const STATUSES = "('confirmed', 'tentative', 'cancelled')";

export const RESPONSES =
  "('needs-action', 'accepted', 'declined', 'tentative')";

export const ROLES = "('chair', 'required', 'optional', 'non-participant')";

/**
 * `jsonb -> column` assignments for an insert, for the optional columns that
 * exist.
 */
export function eventFields(
  ctx: BlockSqlContext,
): readonly (readonly [string, string])[] {
  const e = (column: string) => ctx.col("events", column);
  const features = calendarFeatures(ctx);

  const fields: [string, string][] = [
    [e("title"), "coalesce(v_item ->> 'title', '')"],
    [e("startsAt"), "(v_item ->> 'startsAt')::timestamptz"],
    [e("endsAt"), "(v_item ->> 'endsAt')::timestamptz"],
    [e("allDay"), "coalesce((v_item ->> 'allDay')::boolean, false)"],
    [e("tz"), "coalesce(v_item ->> 'tz', v_tz)"],
    [
      e("status"),
      ctx.cast(
        "events",
        "status",
        "coalesce(v_item ->> 'status', 'confirmed')",
      ),
    ],
  ];

  if (!features.table) {
    fields.push(
      [e("rrule"), "nullif(v_item ->> 'rrule', '')"],
      [e("exdates"), "v_exdates"],
    );
  }

  if (features.rdates && !features.table) {
    fields.push([e("rdates"), "v_rdates"]);
  }

  if (features.access && ctx.has("events", "visibility")) {
    fields.push([
      e("visibility"),
      ctx.cast(
        "events",
        "visibility",
        "coalesce(v_item ->> 'visibility', 'public')",
      ),
    ]);
  }

  for (const column of ["description", "location", "color"] as const) {
    if (ctx.has("events", column)) {
      fields.push([e(column), `v_item ->> '${column}'`]);
    }
  }

  if (ctx.has("events", "kind")) {
    fields.push([
      e("kind"),
      ctx.cast("events", "kind", "coalesce(v_item ->> 'kind', 'event')"),
    ]);
  }

  if (ctx.has("events", "transparency")) {
    fields.push([
      e("transparency"),
      ctx.cast(
        "events",
        "transparency",
        "coalesce(v_item ->> 'transparency', 'opaque')",
      ),
    ]);
  }

  if (ctx.has("events", "autoDecline")) {
    fields.push([
      e("autoDecline"),
      "coalesce((v_item ->> 'autoDecline')::boolean, false)",
    ]);
  }

  if (ctx.has("events", "subjectType") && ctx.has("events", "subjectId")) {
    fields.push(
      [e("subjectType"), "v_item ->> 'subjectType'"],
      [e("subjectId"), "v_item ->> 'subjectId'"],
    );
  }

  return fields;
}

/** An update keeps a column the payload leaves out. */
export function updateSet(ctx: BlockSqlContext): string {
  const keys: Readonly<Record<string, string>> = {
    title: "title",
    startsAt: "startsAt",
    endsAt: "endsAt",
    allDay: "allDay",
    tz: "tz",
    status: "status",
    rrule: "rrule",
    description: "description",
    location: "location",
    color: "color",
    kind: "kind",
    transparency: "transparency",
    autoDecline: "autoDecline",
    subjectType: "subjectType",
    subjectId: "subjectId",
    visibility: "visibility",
  };

  const features = calendarFeatures(ctx);
  const values = new Map(eventFields(ctx));
  const sets: string[] = [];

  for (const [column, key] of Object.entries(keys)) {
    if (!ctx.has("events", column)) {
      continue;
    }

    const ident = ctx.col("events", column);
    const value = values.get(ident);

    if (value === undefined) {
      continue;
    }

    sets.push(
      `${ident} = case when v_item ? '${key}' then ${value} else ${ident} end`,
    );
  }

  if (!features.table) {
    const exdates = ctx.col("events", "exdates");
    sets.push(
      `${exdates} = case when v_item ? 'exdates' then v_exdates else ${exdates} end`,
    );
  }

  if (features.rdates && !features.table) {
    const rdates = ctx.col("events", "rdates");
    sets.push(
      `${rdates} = case when v_item ? 'rdates' then v_rdates else ${rdates} end`,
    );
  }

  sets.push(`${ctx.col("events", "updatedAt")} = now()`);

  return sets.join(",\n    ");
}

/** The keys an event read returns, which no extra column may shadow. */
const EVENT_KEYS: readonly string[] = [
  "id",
  "uid",
  "title",
  "tz",
  "status",
  "rrule",
  "exdates",
  "description",
  "location",
  "color",
  "kind",
  "transparency",
  "autoDecline",
  "attendees",
  "created",
  "fields",
];

/** `options.extraColumns`, which the events table gets. */
export const eventExtras = (
  ctx: BlockSqlContext,
): ReturnType<BlockSqlContext["extraColumns"]> => {
  const features = calendarFeatures(ctx);

  return ctx.extraColumns("events", [
    ...EVENT_KEYS,
    ...(features.rdates ? ["rdates"] : []),
    ...(features.access ? ["visibility", "ownerId"] : []),
  ]);
};

function attendeeRole(
  ctx: BlockSqlContext,
  a: (column: string) => string,
): string {
  if (ctx.has("attendees", "role")) {
    return ctx.label("attendees", "role", a("role"));
  }

  const organizer = ctx.has("attendees", "organizer")
    ? `when ${a("organizer")} then 'chair' `
    : "";

  const optional = ctx.has("attendees", "optional")
    ? `when ${a("optional")} then 'optional' `
    : "";

  return organizer === "" && optional === ""
    ? "'required'"
    : `case ${organizer}${optional}else 'required' end`;
}

function attendeeJson(
  ctx: BlockSqlContext,
  a: (column: string) => string,
): string {
  if (!calendarFeatures(ctx).anyAttendee) {
    return `jsonb_build_object('email', ${a("email")}, 'name', ${a("name")}, 'userId', ${a("user")}, 'role', ${ctx.label("attendees", "role", a("role"))}, 'response', ${ctx.label("attendees", "response", a("response"))})`;
  }

  const column = (key: string, logical: string) =>
    `'${key}', ${ctx.has("attendees", logical) ? a(logical) : "null"}`;

  return `jsonb_build_object('id', ${a("id")}, ${column("email", "email")}, ${column("name", "name")}, 'userId', ${a("user")}, 'role', ${attendeeRole(ctx, a)}, 'response', ${ctx.label("attendees", "response", a("response"))}) || jsonb_build_object(${column("subjectType", "subjectType")}, ${column("subjectId", "subjectId")}, 'organizer', ${ctx.has("attendees", "organizer") ? a("organizer") : `${attendeeRole(ctx, a)} = 'chair'`}, 'optional', ${ctx.has("attendees", "optional") ? a("optional") : `${attendeeRole(ctx, a)} = 'optional'`})`;
}

/** A jsonb object of one event row, aliased `e`. */
export function eventJson(ctx: BlockSqlContext, attendees: string): string {
  const e = (column: string) => `e.${ctx.col("events", column)}`;
  const features = calendarFeatures(ctx);
  const recurrence = recurrenceSql(ctx);

  const optional = (key: string, column: string) =>
    ctx.has("events", column)
      ? `, '${key}', ${column === "kind" || column === "transparency" ? ctx.label("events", column, e(column)) : e(column)}`
      : "";

  const a = (column: string) => `a.${ctx.col("attendees", column)}`;

  const order =
    features.anyAttendee && !ctx.has("attendees", "email")
      ? a("id")
      : a("email");

  const list = ctx.hasTable("attendees")
    ? `, 'attendees', coalesce((select jsonb_agg(${attendeeJson(ctx, a)} order by ${order}) from ${attendees} a where ${a("event")} = ${e("id")}), '[]'::jsonb)`
    : "";

  const rdates = recurrence.rdates("e.");

  const added = `${rdates === undefined ? "" : `, 'rdates', to_jsonb(${rdates})`}${
    features.access && ctx.has("events", "visibility")
      ? `, 'visibility', ${ctx.label("events", "visibility", e("visibility"))}`
      : ""
  }${features.access && ctx.has("events", "owner") ? `, 'ownerId', ${e("owner")}` : ""}`;

  return `jsonb_build_object('id', ${e("id")}, 'calendarId', ${e("calendar")}, 'uid', ${e("uid")}, 'title', ${e("title")}, 'startsAt', ${e("startsAt")}, 'endsAt', ${e("endsAt")}, 'allDay', ${e("allDay")}, 'tz', ${e("tz")}, 'status', ${ctx.label("events", "status", e("status"))}, 'rrule', ${recurrence.rule("e.")}, 'exdates', to_jsonb(${recurrence.exdates("e.")}), 'recurrenceId', ${e("recurrence")}, 'originalStart', ${e("originalStart")}${optional("description", "description")}${optional("location", "location")}${optional("color", "color")}${optional("subjectType", "subjectType")}${optional("subjectId", "subjectId")}) || jsonb_build_object('updatedAt', ${e("updatedAt")}${optional("kind", "kind")}${optional("transparency", "transparency")}${optional("autoDecline", "autoDecline")}${list}${added}${extraFieldsJson("e", eventExtras(ctx))})`;
}
