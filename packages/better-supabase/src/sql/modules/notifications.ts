import type { NotificationsEvents } from "../../blocks/notifications/events.ts";
import type { NotificationDeliveryEventData } from "../../core/block-events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";
import type { NotifyNames } from "./notifications-sql.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addCheck,
  addExtraColumns,
  ownRowPolicies,
  schemaPreamble,
  updatedAt,
  revokeTable,
} from "../shared.ts";
import { subjectCascades, subjectsOption } from "../subjects.ts";
import { accessModel } from "./access-model.ts";
import { providerForUser } from "./access.ts";
import { integerMutations } from "./notifications-items.ts";
import { functions, notifyNames } from "./notifications-sql.ts";
import {
  suppressionContract,
  suppressionsTable,
} from "./notifications-suppressions.ts";
import {
  keepsTemplateKey,
  trackingContract,
  trackingTables,
} from "./notifications-tracking.ts";

/** What `record_delivery_event` writes for each provider event. */
const DELIVERY_PAYLOAD = [
  "notificationId",
  "organizationId",
  "type",
  "channel",
  "deliveryId",
  "provider",
  "providerEventId",
  "subjectType",
  "subjectId",
] as const satisfies readonly (keyof NotificationDeliveryEventData)[];

const DELIVERY_EVENT = {
  subject: "notifications",
  payload: DELIVERY_PAYLOAD,
  retries: true,
};

const EVENTS: BlockSqlEvents<NotificationsEvents> = {
  "notification.created": {
    subject: "notifications",
    payload: ["notificationId", "organizationId", "type", "recipientIds"],
    retries: true,
  },
  "notification.delivered": DELIVERY_EVENT,
  "notification.opened": DELIVERY_EVENT,
  "notification.clicked": DELIVERY_EVENT,
  "notification.bounced": DELIVERY_EVENT,
  "notification.complained": DELIVERY_EVENT,
  "notification.delayed": DELIVERY_EVENT,
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  options: [
    "subjects",
    "channelDefaults",
    "channels",
    "createdEvent",
    "maxRecipients",
    "partitioned",
    "priorities",
    "realtime",
    "topic",
    "updatedEvent",
    "extraColumns",
  ],
  tables: {
    events: {
      name: "notification_events",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "organization_id",
        type: "type",
        actor: "actor_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        subjectLabel: "subject_label",
        summary: "summary",
        actionPath: "action_path",
        priority: "priority",
        data: "data",
        key: "idempotency_key",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      optional: [
        "tenant",
        "actor",
        "subjectType",
        "subjectId",
        "subjectLabel",
        "summary",
        "actionPath",
        "priority",
        "key",
        "createdBy",
      ],
    },
    recipients: {
      name: "notification_recipients",
      lifecycle: { user: "user", tenant: "tenant" },
      columns: {
        id: "id",
        event: "event_id",
        tenant: "organization_id",
        user: "user_id",
        readAt: "read_at",
        dismissedAt: "dismissed_at",
        resolvedAt: "resolved_at",
        deliveredAt: "delivered_at",
        createdAt: "created_at",
      },
      optional: ["tenant", "resolvedAt", "deliveredAt"],
    },
    deliveries: {
      name: "notification_deliveries",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        recipient: "recipient_id",
        tenant: "organization_id",
        channel: "channel",
        status: "status",
        provider: "provider",
        providerMessageId: "provider_message_id",
        error: "error",
        attempts: "attempts",
        attemptedAt: "attempted_at",
        nextAttemptAt: "next_attempt_at",
        deliveredAt: "delivered_at",
        providerStatus: "provider_status",
        providerStatusAt: "provider_status_at",
        templateKey: "template_key",
        createdAt: "created_at",
      },
      optional: [
        "tenant",
        "provider",
        "providerMessageId",
        "error",
        "attempts",
        "nextAttemptAt",
        "deliveredAt",
        "providerStatus",
        "providerStatusAt",
        "templateKey",
      ],
      optionalTable: true,
    },
    deliveryEvents: {
      name: "notification_delivery_events",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        delivery: "delivery_id",
        tenant: "organization_id",
        kind: "kind",
        provider: "provider",
        providerEventId: "provider_event_id",
        occurredAt: "occurred_at",
        detail: "detail",
        createdAt: "created_at",
      },
      optional: ["tenant", "provider"],
      optionalTable: true,
      adoptOnlyWhenMapped: true,
    },
    subscriptions: {
      name: "notification_subscriptions",
      lifecycle: { user: "user", tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "organization_id",
        user: "user_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        level: "level",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["tenant", "updatedAt"],
      optionalTable: true,
    },
    preferences: {
      name: "notification_preferences",
      lifecycle: { user: "user", tenant: "tenant" },
      columns: {
        id: "id",
        user: "user_id",
        tenant: "organization_id",
        type: "type",
        channel: "channel",
        enabled: "enabled",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["tenant", "updatedAt"],
      optionalTable: true,
    },
    suppressions: {
      name: "notification_suppressions",
      lifecycle: { user: "user" },
      columns: {
        id: "id",
        channel: "channel",
        address: "address",
        user: "user_id",
        reason: "reason",
        provider: "provider",
        providerEventId: "provider_event_id",
        detail: "detail",
        createdAt: "created_at",
      },
      optionalTable: true,
      adoptOnlyWhenMapped: true,
    },
  },
  // after_notify predates the before_/after_<entity>_<action> names and keeps
  // its name so apps that define it still get called.
  hooks: ["notification_audience", "before_notification_send", "after_notify"],
};

const TOPIC = /^[A-Za-z0-9:_.\-{}]+$/;
const PLACEHOLDER = /\{(userId|tenantId)\}/g;

function own(n: NotifyNames, table: string, user: string): string {
  return `${n.col(table, user)} = (select auth.uid())`;
}

/**
 * The configured priorities as a CHECK. The constraint is replaced when it
 * lacks a configured priority, because `addCheck` skips an existing name.
 */
function priorityCheck(ctx: BlockSqlContext, n: NotifyNames): string {
  if (!n.has("events", "priority")) {
    return "";
  }

  const table = n.table("events");
  const name = `${ctx.tableName("events").name}_priority_check`;

  const values = ctx
    .list("priorities", ["low", "normal", "high", "urgent"])
    .map(sqlString)
    .join(", ");

  return `
do $$
begin
  if exists (
    select 1 from pg_constraint k, unnest(array[${values}]::text[]) p
    where k.conrelid = ${sqlString(table)}::regclass and k.conname = ${sqlString(name)}
      and pg_get_constraintdef(k.oid) not like '%' || quote_literal(p) || '%'
  ) then
    alter table ${table} drop constraint ${sqlIdent(name)};
  end if;
end;
$$;
${addCheck({ table, name, expression: `${n.col("events", "priority")} in (${values})` })}`;
}

function tables(ctx: BlockSqlContext, n: NotifyNames): string {
  if (!ctx.manages) {
    return "";
  }

  const id = ctx.idType;
  const c = n.col;

  const opt = (table: string, logical: string, definition: string) =>
    n.has(table, logical) ? [`${c(table, logical)} ${definition}`] : [];

  const parts: string[] = [];

  const policy = (table: string, name: string, body: string) => `
drop policy if exists ${sqlIdent(name)} on ${n.table(table)};
create policy ${sqlIdent(name)} on ${n.table(table)} ${body};`;

  parts.push(`
create table if not exists ${n.table("events")} (
  ${[
    `${c("events", "id")} uuid primary key default gen_random_uuid()`,
    ...opt("events", "tenant", id),
    `${c("events", "type")} text not null`,
    ...opt(
      "events",
      "actor",
      "uuid references auth.users (id) on delete set null",
    ),
    ...opt("events", "subjectType", "text"),
    ...opt("events", "subjectId", "text"),
    ...opt("events", "subjectLabel", "text"),
    ...opt("events", "summary", "text"),
    ...opt("events", "actionPath", "text"),
    ...opt("events", "priority", "text not null default 'normal'"),
    `${c("events", "data")} jsonb not null default '{}'`,
    ...opt("events", "key", "text"),
    ...opt(
      "events",
      "createdBy",
      "uuid references auth.users (id) on delete set null",
    ),
    `${c("events", "createdAt")} timestamptz not null default now()`,
  ].join(",\n  ")}
);${
    n.has("events", "key")
      ? `\ncreate unique index if not exists notification_events_key_idx on ${n.table("events")} (${c("events", "key")}${n.has("events", "tenant") ? `, ${c("events", "tenant")}` : ""}) nulls not distinct where ${c("events", "key")} is not null;`
      : ""
  }${
    n.has("events", "subjectType") && n.has("events", "subjectId")
      ? `\ncreate index if not exists notification_events_subject_idx on ${n.table("events")} (${c("events", "subjectType")}, ${c("events", "subjectId")});`
      : ""
  }${n.has("events", "actor") ? `\ncreate index if not exists notification_events_actor_idx on ${n.table("events")} (${c("events", "actor")});` : ""}${n.has("events", "createdBy") ? `\ncreate index if not exists notification_events_created_by_idx on ${n.table("events")} (${c("events", "createdBy")});` : ""}
create index if not exists notification_events_created_at_idx on ${n.table("events")} (${c("events", "createdAt")});${priorityCheck(ctx, n)}${addExtraColumns(n.table("events"), n.extras)}
alter table ${n.table("events")} enable row level security;
${revokeTable(n.table("events"))}
grant select on ${n.table("events")} to authenticated;
grant all on ${n.table("events")} to service_role;

create table if not exists ${n.table("recipients")} (
  ${[
    `${c("recipients", "id")} uuid primary key default gen_random_uuid()`,
    `${c("recipients", "event")} uuid not null references ${n.table("events")} (${c("events", "id")}) on delete cascade`,
    ...opt("recipients", "tenant", id),
    `${c("recipients", "user")} uuid not null references auth.users (id) on delete cascade`,
    `${c("recipients", "readAt")} timestamptz`,
    `${c("recipients", "dismissedAt")} timestamptz`,
    ...opt("recipients", "resolvedAt", "timestamptz"),
    ...opt("recipients", "deliveredAt", "timestamptz not null default now()"),
    `${c("recipients", "createdAt")} timestamptz not null default now()`,
    `unique (${c("recipients", "event")}, ${c("recipients", "user")})`,
  ].join(",\n  ")}
);
create index if not exists notification_recipients_inbox_idx on ${n.table("recipients")} (${c("recipients", "user")}, ${c("recipients", "createdAt")} desc) where ${c("recipients", "dismissedAt")} is null;
create index if not exists notification_recipients_unread_idx on ${n.table("recipients")} (${c("recipients", "user")}) where ${c("recipients", "readAt")} is null and ${c("recipients", "dismissedAt")} is null;
create index if not exists notification_recipients_user_idx on ${n.table("recipients")} (${c("recipients", "user")});
alter table ${n.table("recipients")} enable row level security;
${revokeTable(n.table("recipients"))}
grant select on ${n.table("recipients")} to authenticated;
grant update (${c("recipients", "readAt")}, ${c("recipients", "dismissedAt")}) on ${n.table("recipients")} to authenticated;
grant all on ${n.table("recipients")} to service_role;${policy(
    "recipients",
    "bsb_notification_recipients_read",
    `for select to authenticated using (${own(n, "recipients", "user")})`,
  )}${policy(
    "recipients",
    "bsb_notification_recipients_update",
    `for update to authenticated using (${own(n, "recipients", "user")}) with check (${own(n, "recipients", "user")})`,
  )}${policy(
    "events",
    "bsb_notification_events_read",
    `for select to authenticated using (
  exists (
    select 1 from ${n.table("recipients")} r
    where r.${c("recipients", "event")} = ${n.table("events")}.${c("events", "id")}
      and r.${own(n, "recipients", "user")}
  )
)`,
  )}`);

  if (ctx.hasTable("deliveries")) {
    parts.push(`
create table if not exists ${n.table("deliveries")} (
  ${[
    `${c("deliveries", "id")} uuid primary key default gen_random_uuid()`,
    `${c("deliveries", "recipient")} uuid not null references ${n.table("recipients")} (${c("recipients", "id")}) on delete cascade`,
    ...opt("deliveries", "tenant", id),
    `${c("deliveries", "channel")} text not null`,
    `${c("deliveries", "status")} text not null default 'pending' check (${c("deliveries", "status")} in ('pending', 'sent', 'failed', 'skipped'))`,
    ...opt("deliveries", "provider", "text"),
    ...opt("deliveries", "providerMessageId", "text"),
    ...opt("deliveries", "error", "text"),
    ...opt("deliveries", "attempts", "integer not null default 0"),
    `${c("deliveries", "attemptedAt")} timestamptz`,
    ...opt("deliveries", "nextAttemptAt", "timestamptz not null default now()"),
    ...opt("deliveries", "deliveredAt", "timestamptz"),
    `${c("deliveries", "createdAt")} timestamptz not null default now()`,
    `unique (${c("deliveries", "recipient")}, ${c("deliveries", "channel")})`,
  ].join(",\n  ")}
);
create index if not exists notification_deliveries_pending_idx on ${n.table("deliveries")} (${c("deliveries", "channel")}, ${c("deliveries", "createdAt")}) where ${c("deliveries", "status")} = 'pending';
create index if not exists notification_deliveries_leased_idx on ${n.table("deliveries")} (${c("deliveries", "channel")}, ${c("deliveries", "attemptedAt")}) where ${c("deliveries", "status")} = 'pending' and ${c("deliveries", "attemptedAt")} is not null;
alter table ${n.table("deliveries")} enable row level security;
${revokeTable(n.table("deliveries"))}
grant select on ${n.table("deliveries")} to authenticated;
grant all on ${n.table("deliveries")} to service_role;${policy(
      "deliveries",
      "bsb_notification_deliveries_read",
      `for select to authenticated using (
  exists (
    select 1 from ${n.table("recipients")} r
    where r.${c("recipients", "id")} = ${n.table("deliveries")}.${c("deliveries", "recipient")}
      and r.${own(n, "recipients", "user")}
  )
)`,
    )}`);
  }

  for (const table of ["subscriptions", "preferences"] as const) {
    if (!ctx.hasTable(table)) {
      continue;
    }

    const columns =
      table === "subscriptions"
        ? [
            `${c(table, "id")} uuid primary key default gen_random_uuid()`,
            ...opt(table, "tenant", id),
            `${c(table, "user")} uuid not null references auth.users (id) on delete cascade`,
            `${c(table, "subjectType")} text not null`,
            `${c(table, "subjectId")} text not null`,
            `${c(table, "level")} text not null default 'participating' check (${c(table, "level")} in ('participating', 'all', 'ignore'))`,
            `${c(table, "createdAt")} timestamptz not null default now()`,
          ]
        : [
            `${c(table, "id")} uuid primary key default gen_random_uuid()`,
            `${c(table, "user")} uuid not null references auth.users (id) on delete cascade`,
            ...opt(table, "tenant", id),
            `${c(table, "type")} text not null`,
            `${c(table, "channel")} text not null`,
            `${c(table, "enabled")} boolean not null default true`,
            `${c(table, "createdAt")} timestamptz not null default now()`,
          ];

    const unique =
      table === "subscriptions"
        ? [
            n.has(table, "tenant") ? c(table, "tenant") : undefined,
            c(table, "user"),
            c(table, "subjectType"),
            c(table, "subjectId"),
          ]
        : [
            c(table, "user"),
            n.has(table, "tenant") ? c(table, "tenant") : undefined,
            c(table, "type"),
            c(table, "channel"),
          ];

    const mine = own(n, table, "user");
    parts.push(`
create table if not exists ${n.table(table)} (
  ${columns.join(",\n  ")},
  unique nulls not distinct (${unique.filter((column) => column !== undefined).join(", ")})
);${
      table === "subscriptions"
        ? `
create index if not exists notification_subscriptions_user_idx on ${n.table(table)} (${c(table, "user")});
create index if not exists notification_subscriptions_subject_idx on ${n.table(table)} (${[n.has(table, "tenant") ? c(table, "tenant") : undefined, c(table, "subjectType"), c(table, "subjectId")].filter((column) => column !== undefined).join(", ")});`
        : ""
    }${n.has(table, "updatedAt") ? `\n${updatedAt(n.table(table), c(table, "updatedAt"))}` : ""}
alter table ${n.table(table)} enable row level security;
${revokeTable(n.table(table))}
grant select, insert, update, delete on ${n.table(table)} to authenticated;
grant all on ${n.table(table)} to service_role;
${ownRowPolicies({
  table: n.table(table),
  legacy: `bsb_notification_${table}_own`,
  name: (command) => `bsb_notification_${table}_own_${command}`,
  using: mine,
  check: `${mine}${
    n.has(table, "tenant") && ctx.installed("access")
      ? ` and (${c(table, "tenant")} is null or ${ctx.scope.check(c(table, "tenant"), n.readPermission)})`
      : ""
  }`,
})}`);
  }

  parts.push(suppressionsTable(ctx, n), trackingTables(ctx, n));

  return parts.join("\n");
}

/** The topic as a SQL expression over `new`, and the receive pattern. */
function topic(
  ctx: BlockSqlContext,
  n: NotifyNames,
): { expression: string; pattern: string } {
  const template = ctx.text("topic", "notifications:{userId}");

  if (!TOPIC.test(template) || !template.includes("{userId}")) {
    throw new TypeError(
      `blocks.notifications.options.topic must contain {userId} and only letters, digits, ":", "_", "-", "." and placeholders, not "${template}"`,
    );
  }

  if (template.includes("{tenantId}") && !n.has("recipients", "tenant")) {
    throw new TypeError(
      "blocks.notifications.options.topic uses {tenantId}, but the recipients table has no tenant column",
    );
  }

  const expression: string[] = [];
  const pattern: string[] = [];
  let last = 0;

  for (const match of template.matchAll(PLACEHOLDER)) {
    const literal = template.slice(last, match.index);

    if (literal) {
      expression.push(sqlString(literal));
      pattern.push(sqlString(literal.replaceAll(".", "\\.")));
    }

    if (match[1] === "userId") {
      expression.push(`new.${n.col("recipients", "user")}::text`);
      pattern.push("(select auth.uid())::text");
    } else {
      expression.push(`new.${n.col("recipients", "tenant")}::text`);
      pattern.push("'[^:]+'");
    }

    last = match.index + match[0].length;
  }

  const rest = template.slice(last);

  if (rest) {
    expression.push(sqlString(rest));
    pattern.push(sqlString(rest.replaceAll(".", "\\.")));
  }

  return {
    expression: expression.join(" || "),
    pattern: `'^' || ${pattern.join(" || ")} || '$'`,
  };
}

function realtime(ctx: BlockSqlContext, n: NotifyNames): string {
  const mode = ctx.text("realtime", "broadcast");
  const trigger = ctx.trigger("notification_broadcast");
  const updateTrigger = ctx.trigger("notification_broadcast_update");
  const t = n.table("recipients");

  const drop = `drop trigger if exists ${trigger} on ${t};
drop trigger if exists ${updateTrigger} on ${t};`;

  switch (mode) {
    case "none": {
      return drop;
    }

    case "changes": {
      return `${drop}
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_rel pr
      join pg_publication p on p.oid = pr.prpubid
      where p.pubname = 'supabase_realtime' and pr.prrelid = ${sqlString(t)}::regclass
    ) then
    execute format('alter publication supabase_realtime add table %s', ${sqlString(t)});
  end if;
end;
$$;`;
    }

    case "broadcast": {
      const { expression, pattern } = topic(ctx, n);

      const created = sqlString(
        ctx.text("createdEvent", "notification_created"),
      );

      const updated = sqlString(
        ctx.text("updatedEvent", "notification_updated"),
      );

      const receive = ctx.trigger("notifications_receive");

      const changed = (["readAt", "dismissedAt", "resolvedAt"] as const)
        .filter((logical) => n.has("recipients", logical))
        .map((logical) => n.col("recipients", logical));

      const tenant = n.has("recipients", "tenant")
        ? `, 'tenant', new.${n.col("recipients", "tenant")}`
        : "";

      return `
-- Tells the recipient's private topic that a notification arrived or changed.
-- The payload carries ids only; the client reads the row through RLS.
create or replace function ${ctx.fn("broadcast_notification")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('id', new.${n.col("recipients", "id")}, 'event_id', new.${n.col("recipients", "event")}, 'operation', lower(tg_op)${tenant}),
    case when tg_op = 'INSERT' then ${created} else ${updated} end,
    ${expression},
    true
  );
  return null;
end;
$$;
revoke execute on function ${ctx.fn("broadcast_notification")}() from public, anon, authenticated;
${drop}
create trigger ${trigger} after insert on ${t}
  for each row execute function ${ctx.fn("broadcast_notification")}();
create trigger ${updateTrigger} after update of ${changed.join(", ")} on ${t}
  for each row when (${changed.map((column) => `old.${column} is distinct from new.${column}`).join(" or ")})
  execute function ${ctx.fn("broadcast_notification")}();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists ${receive} on realtime.messages;
    create policy ${receive} on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) ~ (${pattern}));
  end if;
end;
$$;`;
    }

    default: {
      throw new TypeError(
        `blocks.notifications.options.realtime must be "broadcast", "changes" or "none", not "${mode}"`,
      );
    }
  }
}

/**
 * `options.subjects` with `cascade: true`: deleting a subject row deletes its
 * notifications (recipients and deliveries follow by foreign key) and the
 * subscriptions to it. The deletes match the subject's tenant too, so they use
 * indexes that lead with the tenant column.
 */
function subjectCleanup(ctx: BlockSqlContext, n: NotifyNames): string {
  const subjects = subjectsOption(ctx, [], { tenantless: true, hyphens: true });

  if (!subjects.some(([, subject]) => subject.cascade)) {
    return "";
  }

  if (!n.has("events", "subjectType") || !n.has("events", "subjectId")) {
    throw new TypeError(
      "blocks.notifications.options.subjects with cascade needs the subjectType and subjectId columns of the events table",
    );
  }

  const tables = ctx.hasTable("subscriptions")
    ? ["events", "subscriptions"]
    : ["events"];

  const removeFrom = (table: string, tenant: boolean) =>
    `delete from ${n.table(table)} x where ${
      tenant && n.has(table, "tenant")
        ? `x.${n.col(table, "tenant")} = v_tenant::${ctx.idType} and `
        : ""
    }x.${n.col(table, "subjectType")} = v_type and x.${n.col(table, "subjectId")} = v_id;`;

  const remove = (tenant: boolean) =>
    tables.map((table) => removeFrom(table, tenant)).join("\n    ");

  if (!tables.some((table) => n.has(table, "tenant"))) {
    return subjectCascades(ctx, subjects, remove(false));
  }

  return subjectCascades(
    ctx,
    subjects,
    `if v_tenant is null then
    ${remove(false)}
  else
    ${remove(true)}
  end if;`,
    { tenant: true },
  );
}

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const n = notifyNames(
    ctx,
    accessModel(ctx) !== "provider" || providerForUser(layout).permitted,
  );

  return [
    `${schemaPreamble(ctx)}${tables(ctx, n)}`,
    functions(ctx, n, layout),
    realtime(ctx, n),
    subjectCleanup(ctx, n),
  ].join("\n");
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const fns: BlockSqlContractFunction[] = [
    { name: "notify", args: ["jsonb"], returns: "uuid" },
    { name: "send_notification", args: ["jsonb"], returns: "jsonb" },
    { name: "send_notifications", args: ["jsonb"], returns: "jsonb" },
    { name: "get_notification", args: ["uuid"], returns: "jsonb" },
    {
      name: "notification_enabled",
      args: ["uuid", "{id}", "text", "text"],
      returns: "boolean",
    },
    {
      name: "list_notifications",
      args: [
        "{id}",
        "text",
        "text[]",
        "timestamp with time zone",
        "integer",
        "uuid",
        "text[]",
        "text",
        "boolean",
        "boolean",
        "boolean",
      ],
      returns: "jsonb",
    },
    {
      name: "notification_page",
      args: [
        "{id}",
        "text",
        "text[]",
        "text[]",
        "text",
        "integer",
        "integer",
        "boolean",
        "boolean",
        "boolean",
      ],
      returns: "jsonb",
    },
    { name: "notification_counts", args: ["{id}", "text[]"], returns: "jsonb" },
    {
      name: "mark_notifications_read",
      args: ["uuid[]", "{id}"],
      returns: "jsonb",
    },
    {
      name: "mark_notifications_unread",
      args: ["uuid[]", "{id}"],
      returns: "jsonb",
    },
    { name: "dismiss_notifications", args: ["uuid[]"], returns: "jsonb" },
    {
      name: "purge_notifications",
      args: ["interval", "integer"],
      returns: "integer",
    },
  ];

  if (ctx.has("recipients", "resolvedAt")) {
    fns.push({
      name: "resolve_notifications",
      args: ["text", "text", "text", "{id}"],
      returns: "jsonb",
    });
  }

  if (ctx.hasTable("subscriptions")) {
    fns.push(
      {
        name: "set_notification_subscription",
        args: ["text", "text", "text", "{id}", "uuid", "boolean"],
        returns: "void",
      },
      {
        name: "list_notification_subscriptions",
        args: ["{id}", "text", "text"],
        returns: "jsonb",
      },
    );
  }

  if (ctx.hasTable("preferences")) {
    fns.push(
      {
        name: "set_notification_preference",
        args: ["text", "text", "boolean", "{id}"],
        returns: "void",
      },
      {
        name: "list_notification_preferences",
        args: ["{id}"],
        returns: "jsonb",
      },
    );
  }

  if (ctx.hasTable("deliveries")) {
    fns.push(
      {
        name: "claim_notification_deliveries",
        args: ["text", "integer", "interval", "integer"],
        returns: "jsonb",
      },
      {
        name: "complete_notification_delivery",
        args: [
          "uuid",
          "text",
          "text",
          "text",
          "text",
          "integer",
          ...(keepsTemplateKey(ctx) ? ["text"] : []),
        ],
        returns: "text",
      },
    );
  }

  fns.push(...suppressionContract(ctx), ...trackingContract(ctx));

  return fns;
}

export const NOTIFICATIONS: BlockSqlDefinition = {
  name: "notifications",
  title: "Notifications",
  description:
    "In-app notifications sent through a security definer notify(): one event per change, per-recipient read, dismissed and resolved state, per-channel deliveries, subject subscriptions, preferences with a tenant override, and realtime on a private topic.",
  requires: ["updated-at"],
  integrates: ["access", "profiles", "tenant", "data-lifecycle"],
  providerFunctions: ["idsWithFor"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 8,
  names: NAMES,
  contract,
  upgrades: [
    {
      from: 1,
      description:
        "The broadcast trigger fires on an update only when read_at, dismissed_at or resolved_at changes; new indexes serve unread counts, user deletes, purges and lost delivery leases.",
      sql: () => "",
    },
    {
      from: 2,
      description:
        "list_notifications takes subject_types and search and a settled status; notification_page pages with an offset and a total; mark_notifications_unread and the subscription and preference readers are new.",
      sql: (ctx) =>
        `drop function if exists ${ctx.fn("list_notifications")}(${ctx.idType}, text, text[], timestamptz, integer, uuid);`,
    },
    {
      from: 3,
      description:
        "list_notifications and notification_page filter on read, resolved and dismissed; mark_notifications_read, mark_notifications_unread, dismiss_notifications and resolve_notifications return the count and the caller's changed notifications; get_notification and send_notification are new.",
      sql: (ctx) =>
        [
          `drop function if exists ${ctx.fn("list_notifications")}(${ctx.idType}, text, text[], timestamptz, integer, uuid, text[], text);`,
          `drop function if exists ${ctx.fn("notification_page")}(${ctx.idType}, text, text[], text[], text, integer, integer);`,
          integerMutations(ctx),
        ].join("\n"),
    },
    {
      from: 4,
      description:
        "notification_suppressions holds addresses a channel no longer sends to after a bounce or a complaint; claim_notification_deliveries returns each delivery's suppression, and suppress_notification_address, unsuppress_notification_address and list_notification_suppressions are new.",
      sql: () => "",
    },
    {
      from: 5,
      description:
        "notification_delivery_events stores what a provider reports about a sent message; deliveries gain provider_status, provider_status_at and template_key; record_delivery_event and list_subject_deliveries are new, complete_notification_delivery takes template_key, and notification.delivered, opened, clicked, bounced, complained and delayed carry the subject.",
      sql: () => "",
    },
    {
      from: 6,
      description:
        "purge_notifications keeps notifications for the data-lifecycle retention policy and skips those under a legal hold.",
      sql: () => "",
    },
    {
      from: 7,
      description:
        "send_notifications(events) sends a batch in one call, with send_notification's checks per notification and a {notification} or {error} result each. options.partitioned partitions a new notification_delivery_events table by month on created_at and applies to new tables only.",
      sql: () => "",
    },
  ],
  build,
  topics: (ctx) =>
    ctx.text("realtime", "broadcast") === "broadcast"
      ? [ctx.text("topic", "notifications:{userId}")]
      : [],
};
