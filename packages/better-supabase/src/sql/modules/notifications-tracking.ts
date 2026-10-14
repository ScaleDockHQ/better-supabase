import type { ModuleContext, ModuleContractFunction } from "../context.ts";
import type { NotifyNames } from "./notifications-sql.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  NOTHING,
  SERVICE_CALLER,
  fail,
  pageSize,
  revokeTable,
  serviceGrant,
} from "../shared.ts";
import { suppressing } from "./notifications-suppressions.ts";

/**
 * What a provider reports about a sent message, from the least to the most
 * final: a delivery's `provider_status` only moves forward in this order.
 */
const DELIVERY_EVENT_KINDS = [
  "delayed",
  "delivered",
  "opened",
  "clicked",
  "bounced",
  "complained",
] as const;

const KINDS = `array[${DELIVERY_EVENT_KINDS.map(sqlString).join(", ")}]::text[]`;

/**
 * Whether the module tracks provider events. It needs deliveries with a
 * provider message id, and an adopted module needs `tables.deliveryEvents`
 * mapped explicitly, so an adopter that predates it keeps installing.
 */
const tracking = (ctx: ModuleContext): boolean =>
  ctx.hasTable("deliveries") &&
  ctx.hasTable("deliveryEvents") &&
  ctx.has("deliveries", "providerMessageId") &&
  (ctx.manages || ctx.config.tables["deliveryEvents"] !== undefined);

/** Whether `complete_notification_delivery` takes and stores a template key. */
export const keepsTemplateKey = (ctx: ModuleContext): boolean =>
  tracking(ctx) && ctx.has("deliveries", "templateKey");

/**
 * The provider status and template key columns on deliveries, the lookup
 * index for webhooks, and the `notification_delivery_events` table that
 * recipients read for their own deliveries.
 */
export function trackingTables(ctx: ModuleContext, n: NotifyNames): string {
  if (!ctx.manages || !tracking(ctx)) return "";
  const d = (logical: string) => n.col("deliveries", logical);
  const e = (logical: string) => n.col("deliveryEvents", logical);
  const deliveries = n.table("deliveries");
  const t = n.table("deliveryEvents");
  const columns = [
    n.has("deliveries", "providerStatus")
      ? `alter table ${deliveries} add column if not exists ${d("providerStatus")} text check (${d("providerStatus")} in (${DELIVERY_EVENT_KINDS.map(sqlString).join(", ")}));`
      : "",
    n.has("deliveries", "providerStatusAt")
      ? `alter table ${deliveries} add column if not exists ${d("providerStatusAt")} timestamptz;`
      : "",
    n.has("deliveries", "templateKey")
      ? `alter table ${deliveries} add column if not exists ${d("templateKey")} text;`
      : "",
    `create index if not exists notification_deliveries_provider_message_idx on ${deliveries} (${[
      n.has("deliveries", "provider") ? d("provider") : undefined,
      d("providerMessageId"),
    ]
      .filter((column) => column !== undefined)
      .join(", ")}) where ${d("providerMessageId")} is not null;`,
  ].filter((line) => line !== "");
  const policy = sqlIdent("bs_notification_delivery_events_read");
  return `
${columns.join("\n")}

create table if not exists ${t} (
  ${[
    `${e("id")} uuid primary key default gen_random_uuid()`,
    `${e("delivery")} uuid not null references ${deliveries} (${d("id")}) on delete cascade`,
    ...(n.has("deliveryEvents", "tenant")
      ? [`${e("tenant")} ${ctx.idType}`]
      : []),
    `${e("kind")} text not null check (${e("kind")} in (${DELIVERY_EVENT_KINDS.map(sqlString).join(", ")}))`,
    ...(n.has("deliveryEvents", "provider") ? [`${e("provider")} text`] : []),
    `${e("providerEventId")} text unique`,
    `${e("occurredAt")} timestamptz not null default now()`,
    `${e("detail")} jsonb not null default '{}'`,
    `${e("createdAt")} timestamptz not null default now()`,
  ].join(",\n  ")}
);
create index if not exists notification_delivery_events_delivery_idx on ${t} (${e("delivery")}, ${e("occurredAt")});
alter table ${t} enable row level security;
${revokeTable(t)}
grant select on ${t} to authenticated;
grant all on ${t} to service_role;
drop policy if exists ${policy} on ${t};
create policy ${policy} on ${t} for select to authenticated using (
  exists (
    select 1 from ${deliveries} d
    join ${n.table("recipients")} r on r.${n.col("recipients", "id")} = d.${d("recipient")}
    where d.${d("id")} = ${t}.${e("delivery")}
      and r.${n.col("recipients", "user")} = (select auth.uid())
  )
);`;
}

/** The SQL for one kind's outbox event, inside `record_delivery_event`. */
function recordKinds(ctx: ModuleContext, fn: string): string {
  const statements = DELIVERY_EVENT_KINDS.map((kind) => ({
    kind,
    statement: ctx.record({
      type: `notification.${kind}`,
      payload: `jsonb_build_object('notificationId', v_event, 'organizationId', v_tenant::text, 'type', v_type, 'channel', v_channel, 'deliveryId', v_delivery, 'provider', ${fn}.provider, 'providerEventId', ${fn}.provider_event_id, 'subjectType', v_subject_type, 'subjectId', v_subject_id)`,
      subject: "'notifications/' || v_event::text",
      tenant: "v_tenant",
      key: `'notification.${kind}:' || v_row::text`,
      audit: false,
    }),
  }));
  if (statements.every(({ statement }) => statement === NOTHING)) return "";
  const branches = statements.map(
    ({ kind, statement }, index) =>
      `${index === 0 ? "if" : "elsif"} v_kind = ${sqlString(kind)} then
      ${statement}`,
  );
  return `
    ${branches.join("\n    ")}
    end if;`;
}

/**
 * `record_delivery_event` for the service (provider webhooks) and
 * `list_subject_deliveries`, which a sender reads for one record.
 */
export function trackingFunctions(ctx: ModuleContext, n: NotifyNames): string {
  if (!tracking(ctx)) return "";
  const id = ctx.idType;
  const d = (logical: string) => n.col("deliveries", logical);
  const r = (logical: string) => n.col("recipients", logical);
  const ev = (logical: string) => n.col("events", logical);
  const e = (logical: string) => n.col("deliveryEvents", logical);
  const record = "record_delivery_event";
  const list = "list_subject_deliveries";
  const subjects =
    n.has("events", "subjectType") && n.has("events", "subjectId");
  const tenant = n.has("deliveries", "tenant")
    ? `d.${d("tenant")}`
    : n.has("events", "tenant")
      ? `ev.${ev("tenant")}`
      : `null::${id}`;
  const status = n.has("deliveries", "providerStatus");
  const statusAt = n.has("deliveries", "providerStatusAt");
  const statusSet = [
    `${d("providerStatus")} = v_kind`,
    ...(statusAt ? [`${d("providerStatusAt")} = v_at`] : []),
  ];
  const updateStatus = status
    ? `
    update ${n.table("deliveries")} d
    set ${statusSet.join(", ")}
    where d.${d("id")} = v_delivery
      and coalesce(array_position(${KINDS}, d.${d("providerStatus")}), 0) <= array_position(${KINDS}, v_kind);`
    : "";
  const suppress = suppressing(ctx)
    ? `
    if v_kind in ('bounced', 'complained') and coalesce(${record}.suppress, true) then
      select u.email into v_email from auth.users u where u.id = v_user;
      if v_email is not null and btrim(v_email) <> '' then
        perform ${ctx.fn("suppress_notification_address")}(
          v_email,
          case when v_kind = 'bounced' then 'bounce' else 'complaint' end,
          v_channel,
          ${record}.provider,
          ${record}.provider_event_id,
          coalesce(${record}.detail, '{}')
        );
      end if;
    end if;`
    : "";
  const insertColumns = [
    e("delivery"),
    ...(n.has("deliveryEvents", "tenant") ? [e("tenant")] : []),
    e("kind"),
    ...(n.has("deliveryEvents", "provider") ? [e("provider")] : []),
    e("providerEventId"),
    e("occurredAt"),
    e("detail"),
  ];
  const insertValues = [
    "v_delivery",
    ...(n.has("deliveryEvents", "tenant") ? ["v_tenant"] : []),
    "v_kind",
    ...(n.has("deliveryEvents", "provider") ? [`${record}.provider`] : []),
    `nullif(${record}.provider_event_id, '')`,
    "v_at",
    `coalesce(${record}.detail, '{}')`,
  ];
  const parts = [
    `
-- Records what a provider reported about a sent message (a webhook): finds
-- the delivery by the provider's message id, stores the event once per
-- provider event id, moves provider_status forward, suppresses the
-- recipient's address on a bounce or a complaint (unless suppress is
-- false), and writes notification.<kind>. Null when no delivery matches.
create or replace function ${ctx.fn(record)}(provider text, provider_message_id text, kind text, provider_event_id text default null, occurred_at timestamptz default null, detail jsonb default '{}', suppress boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_kind text := ${record}.kind;
  v_at timestamptz := coalesce(${record}.occurred_at, now());
  v_delivery uuid;
  v_channel text;
  v_user uuid;
  v_event uuid;
  v_type text;
  v_tenant ${id};
  v_subject_type text;
  v_subject_id text;
  v_row uuid;${suppressing(ctx) ? "\n  v_email text;" : ""}
begin
  if v_kind is null or not (v_kind = any(${KINDS})) then
    ${fail("NOTIFICATION_DELIVERY_EVENT_KIND", `kind must be ${DELIVERY_EVENT_KINDS.join(", ")}`, "22023")}
  end if;
  if ${record}.provider_message_id is null or btrim(${record}.provider_message_id) = '' then
    ${fail("NOTIFICATION_DELIVERY_MESSAGE_ID", "provider_message_id is required", "22023")}
  end if;
  select d.${d("id")}, d.${d("channel")}, rc.${r("user")}, ev.${ev("id")}, ev.${ev("type")}, ${tenant},
    ${subjects ? `coalesce(ev.${ev("subjectType")}, 'notification')` : "'notification'"},
    ${subjects ? `coalesce(ev.${ev("subjectId")}, ev.${ev("id")}::text)` : `ev.${ev("id")}::text`}
  into v_delivery, v_channel, v_user, v_event, v_type, v_tenant, v_subject_type, v_subject_id
  from ${n.table("deliveries")} d
  join ${n.table("recipients")} rc on rc.${r("id")} = d.${d("recipient")}
  join ${n.table("events")} ev on ev.${ev("id")} = rc.${r("event")}
  where d.${d("providerMessageId")} = ${record}.provider_message_id${
    n.has("deliveries", "provider")
      ? `
    and (${record}.provider is null or d.${d("provider")} = ${record}.provider)`
      : ""
  }
  order by d.${d("createdAt")} desc
  limit 1;
  if v_delivery is null then
    return null;
  end if;
  insert into ${n.table("deliveryEvents")} (${insertColumns.join(", ")})
  values (${insertValues.join(", ")})
  on conflict (${e("providerEventId")}) do nothing
  returning ${e("id")} into v_row;
  if v_row is not null then${updateStatus}${suppress}${recordKinds(ctx, record)}
  end if;
  return jsonb_build_object(
    'delivery_id', v_delivery,
    'notification_id', v_event,
    'tenant', v_tenant,
    'type', v_type,
    'channel', v_channel,
    'user_id', v_user,
    'subject_type', v_subject_type,
    'subject_id', v_subject_id,
    'kind', v_kind,
    'provider_status', ${status ? `(select d.${d("providerStatus")} from ${n.table("deliveries")} d where d.${d("id")} = v_delivery)` : "null"},
    'recorded', v_row is not null
  );
end;
$$;
${serviceGrant(`${ctx.fn(record)}(text, text, text, text, timestamptz, jsonb, boolean)`)}`,
  ];
  if (subjects) {
    const fields: [string, string][] = [
      ["id", `d.${d("id")}`],
      ["notification_id", `ev.${ev("id")}`],
      ["type", `ev.${ev("type")}`],
      ["channel", `d.${d("channel")}`],
      ["user_id", `rc.${r("user")}`],
      ["status", `d.${d("status")}`],
      ["provider_message_id", `d.${d("providerMessageId")}`],
      ["created_at", `d.${d("createdAt")}`],
    ];
    const optional: [string, string][] = [
      ["provider", "provider"],
      ["provider_status", "providerStatus"],
      ["provider_status_at", "providerStatusAt"],
      ["template_key", "templateKey"],
      ["error", "error"],
      ["attempts", "attempts"],
      ["delivered_at", "deliveredAt"],
    ];
    for (const [key, logical] of optional) {
      if (n.has("deliveries", logical)) fields.push([key, `d.${d(logical)}`]);
    }
    fields.push([
      "events",
      `(
        select coalesce(jsonb_agg(jsonb_build_object('kind', de.${e("kind")}, 'occurred_at', de.${e("occurredAt")}, 'detail', de.${e("detail")}) order by de.${e("occurredAt")}, de.${e("createdAt")}), '[]')
        from ${n.table("deliveryEvents")} de where de.${e("delivery")} = d.${d("id")}
      )`,
    ]);
    const access = ctx.installed("access");
    const allowed = access
      ? `(${SERVICE_CALLER}) or (${list}.tenant is not null and coalesce(better_supabase.member_can(auth.uid(), ${list}.tenant, ${n.sendPermission}), false))`
      : SERVICE_CALLER;
    const signature = `${ctx.fn(list)}(text, text, ${id}, integer)`;
    parts.push(`
-- The deliveries of the notifications about one record, newest first, each
-- with its provider events: for a record's "emails sent" panel. The service
-- reads every tenant's; a member needs the send permission in tenant.
create or replace function ${ctx.fn(list)}(subject_type text, subject_id text, tenant ${id} default null, max_items integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (${allowed}) then
    ${fail("NOTIFICATION_FORBIDDEN", "Not allowed to read this record's deliveries")}
  end if;
  return (
    select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
    from (
      select jsonb_build_object(${fields.map(([key, value]) => `'${key}', ${value}`).join(", ")}) as item,
        d.${d("createdAt")} as created_at, d.${d("id")} as id
      from ${n.table("deliveries")} d
      join ${n.table("recipients")} rc on rc.${r("id")} = d.${d("recipient")}
      join ${n.table("events")} ev on ev.${ev("id")} = rc.${r("event")}
      where ev.${ev("subjectType")} = ${list}.subject_type
        and ev.${ev("subjectId")} = ${list}.subject_id${
          n.has("events", "tenant")
            ? `
        and (${list}.tenant is null or ev.${ev("tenant")} = ${list}.tenant)`
            : ""
        }
      order by d.${d("createdAt")} desc, d.${d("id")} desc
      limit ${pageSize(`${list}.max_items`, 50, 200)}
    ) x
  );
end;
$$;
${
  access
    ? `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`
    : serviceGrant(signature)
}`);
  }
  return parts.join("\n");
}

export function trackingContract(
  ctx: ModuleContext,
): readonly ModuleContractFunction[] {
  if (!tracking(ctx)) return [];
  const fns: ModuleContractFunction[] = [
    {
      name: "record_delivery_event",
      args: [
        "text",
        "text",
        "text",
        "text",
        "timestamp with time zone",
        "jsonb",
        "boolean",
      ],
      returns: "jsonb",
    },
  ];
  if (ctx.has("events", "subjectType") && ctx.has("events", "subjectId")) {
    fns.push({
      name: "list_subject_deliveries",
      args: ["text", "text", "{id}", "integer"],
      returns: "jsonb",
    });
  }
  return fns;
}
