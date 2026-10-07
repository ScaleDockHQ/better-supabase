import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition, ModuleLayout } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { schemaPreamble, updatedAt } from "../shared.ts";
import { accessModel } from "./access-model.ts";
import { permdockForUser } from "./access.ts";
import {
  functions,
  type NotifyNames,
  notifyNames,
} from "./notifications-sql.ts";

const NAMES: ModuleNames = {
  options: [
    "channelDefaults",
    "channels",
    "createdEvent",
    "maxRecipients",
    "priorities",
    "realtime",
    "topic",
    "updatedEvent",
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
      ],
      optionalTable: true,
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
  },
  hooks: ["notification_audience", "after_notify"],
};

const TOPIC = /^[A-Za-z0-9:_.\-{}]+$/;
const PLACEHOLDER = /\{(userId|tenantId)\}/g;

function own(n: NotifyNames, table: string, user: string): string {
  return `${n.col(table, user)} = (select auth.uid())`;
}

function tables(ctx: ModuleContext, n: NotifyNames): string {
  if (!ctx.manages) return "";
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
alter table ${n.table("events")} enable row level security;
revoke all on ${n.table("events")} from anon, authenticated;
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
alter table ${n.table("recipients")} enable row level security;
revoke all on ${n.table("recipients")} from anon, authenticated;
grant select on ${n.table("recipients")} to authenticated;
grant update (${c("recipients", "readAt")}, ${c("recipients", "dismissedAt")}) on ${n.table("recipients")} to authenticated;
grant all on ${n.table("recipients")} to service_role;${policy(
    "recipients",
    "bs_notification_recipients_read",
    `for select to authenticated using (${own(n, "recipients", "user")})`,
  )}${policy(
    "recipients",
    "bs_notification_recipients_update",
    `for update to authenticated using (${own(n, "recipients", "user")}) with check (${own(n, "recipients", "user")})`,
  )}${policy(
    "events",
    "bs_notification_events_read",
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
alter table ${n.table("deliveries")} enable row level security;
revoke all on ${n.table("deliveries")} from anon, authenticated;
grant select on ${n.table("deliveries")} to authenticated;
grant all on ${n.table("deliveries")} to service_role;${policy(
      "deliveries",
      "bs_notification_deliveries_read",
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
    if (!ctx.hasTable(table)) continue;
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
revoke all on ${n.table(table)} from anon, authenticated;
grant select, insert, update, delete on ${n.table(table)} to authenticated;
grant all on ${n.table(table)} to service_role;${policy(
      table,
      `bs_notification_${table}_own`,
      `for all to authenticated using (${mine}) with check (${mine}${
        n.has(table, "tenant") && ctx.installed("access")
          ? ` and (${c(table, "tenant")} is null or coalesce(better_supabase.can('tenant', ${c(table, "tenant")}, ${n.readPermission}), false))`
          : ""
      })`,
    )}`);
  }
  return parts.join("\n");
}

/** The topic as a SQL expression over `new`, and the receive pattern. */
function topic(
  ctx: ModuleContext,
  n: NotifyNames,
): { expression: string; pattern: string } {
  const template = ctx.text("topic", "notifications:{userId}");
  if (!TOPIC.test(template) || !template.includes("{userId}")) {
    throw new TypeError(
      `sql.modules.notifications.options.topic must contain {userId} and only letters, digits, ":", "_", "-", "." and placeholders, not "${template}"`,
    );
  }
  if (template.includes("{tenantId}") && !n.has("recipients", "tenant")) {
    throw new TypeError(
      "sql.modules.notifications.options.topic uses {tenantId}, but the recipients table has no tenant column",
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

function realtime(ctx: ModuleContext, n: NotifyNames): string {
  const mode = ctx.text("realtime", "broadcast");
  const trigger = ctx.trigger("notification_broadcast");
  const t = n.table("recipients");
  switch (mode) {
    case "none":
      return `drop trigger if exists ${trigger} on ${t};`;
    case "changes":
      return `drop trigger if exists ${trigger} on ${t};
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
    case "broadcast": {
      const { expression, pattern } = topic(ctx, n);
      const created = sqlString(
        ctx.text("createdEvent", "notification_created"),
      );
      const updated = sqlString(
        ctx.text("updatedEvent", "notification_updated"),
      );
      const receive = ctx.trigger("notifications_receive");
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
drop trigger if exists ${trigger} on ${t};
create trigger ${trigger} after insert or update on ${t}
  for each row execute function ${ctx.fn("broadcast_notification")}();
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
    default:
      throw new TypeError(
        `sql.modules.notifications.options.realtime must be "broadcast", "changes" or "none", not "${mode}"`,
      );
  }
}

function build(ctx: ModuleContext, layout: ModuleLayout): string {
  if (ctx.mode === "custom") return "";
  const n = notifyNames(
    ctx,
    accessModel(ctx) !== "permdock" || permdockForUser(ctx, layout).permitted,
  );
  return [
    `${schemaPreamble(ctx)}${tables(ctx, n)}`,
    functions(ctx, n),
    realtime(ctx, n),
  ].join("\n");
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  const fns: ModuleContractFunction[] = [
    { name: "notify", args: ["jsonb"], returns: "uuid" },
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
      ],
      returns: "jsonb",
    },
    {
      name: "notification_counts",
      args: ["{id}", "text[]"],
      returns: "jsonb",
    },
    {
      name: "mark_notifications_read",
      args: ["uuid[]", "{id}"],
      returns: "integer",
    },
    { name: "dismiss_notifications", args: ["uuid[]"], returns: "integer" },
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
      returns: "integer",
    });
  }
  if (ctx.hasTable("subscriptions")) {
    fns.push({
      name: "set_notification_subscription",
      args: ["text", "text", "text", "{id}", "uuid"],
      returns: "void",
    });
  }
  if (ctx.hasTable("preferences")) {
    fns.push({
      name: "set_notification_preference",
      args: ["text", "text", "boolean", "{id}"],
      returns: "void",
    });
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
        args: ["uuid", "text", "text", "text", "text", "integer"],
        returns: "text",
      },
    );
  }
  return fns;
}

export const NOTIFICATIONS: ModuleDefinition = {
  name: "notifications",
  title: "Notifications",
  description:
    "In-app notifications sent through a security definer notify(): one event per change, per-recipient read, dismissed and resolved state, per-channel deliveries, subject subscriptions, preferences with a tenant override, and realtime on a private topic.",
  requires: ["updated-at"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
  topics: (ctx) =>
    ctx.text("realtime", "broadcast") === "broadcast"
      ? [ctx.text("topic", "notifications:{userId}")]
      : [],
};
