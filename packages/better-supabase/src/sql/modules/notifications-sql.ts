import type { ExtraColumn, BlockSqlContext } from "../context.ts";
import type { BlockSqlLayout } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import {
  SERVICE_CALLER,
  batchFunction,
  pageSize,
  fail,
  writeExtraColumns,
} from "../shared.ts";
import {
  channelDefaults,
  permissionAudience,
} from "./notifications-audience.ts";
import { consentGate } from "./notifications-consent.ts";
import { delivery, purge } from "./notifications-delivery.ts";
import { digestFunctions, heldStatus, notOff } from "./notifications-digest.ts";
import {
  changedJson,
  integerMutations,
  itemJson,
} from "./notifications-items.ts";
import { readers } from "./notifications-readers.ts";
import { suppressionFunctions } from "./notifications-suppressions.ts";
import { trackingFunctions } from "./notifications-tracking.ts";
import { accessModel, OPERATIONS } from "./permissions-model.ts";
import { hasAvatarPath } from "./profiles.ts";

export interface NotifyNames {
  readonly table: (table: string) => string;
  readonly col: (table: string, logical: string) => string;
  readonly has: (table: string, logical: string) => boolean;
  /** SQL literals of the permission keys. */
  readonly sendPermission: string;
  readonly readPermission: string;
  /** Whether `member_can` answers for users other than the caller. */
  readonly answersForOthers: boolean;
  /**
   * The columns your schema files add of the events table, written from
   * `notification.fields`.
   */
  readonly extras: readonly ExtraColumn[];
}

/** The keys an inbox item returns next to the event's columns (`itemJson`). */
const ITEM_KEYS = ["event_id", "read_at", "actor_id", "resolved_at", "fields"];

export function notifyNames(
  ctx: BlockSqlContext,
  answersForOthers: boolean = accessModel(ctx) !== "provider",
): NotifyNames {
  return {
    answersForOthers,
    extras: ctx.extraColumns("events", ITEM_KEYS),
    table: (table) => ctx.table(table),
    col: (table, logical) => ctx.col(table, logical),
    has: (table, logical) => ctx.hasTable(table) && ctx.has(table, logical),
    sendPermission: ctx.permission("send", OPERATIONS["notifications.send"]),
    readPermission: ctx.permission("read", OPERATIONS["notifications.read"]),
  };
}

const NAME = /^[a-z][a-z0-9_]*$/;

/**
 * The (member, channel) pairs that want this notification, in one query: each
 * pair's most specific preference, or the channel default.
 */
function wanted(ctx: BlockSqlContext, n: NotifyNames): string {
  const defaults = channelDefaults(ctx, "c");

  if (!ctx.hasTable("preferences")) {
    return `select x as member, c as channel
    from unnest(v_recipients) x cross join unnest(v_channels) c
    where ${defaults}`;
  }

  const p = (logical: string) => n.col("preferences", logical);
  const tenant = n.has("preferences", "tenant");

  return `select w.member, w.channel from (
      select distinct on (x, c) x as member, c as channel, coalesce(p.${p("enabled")}, ${defaults})${notOff(n, "p")} as enabled
      from unnest(v_recipients) x cross join unnest(v_channels) c
      left join ${n.table("preferences")} p
        on p.${p("user")} = x and p.${p("channel")} = c
        and (p.${p("type")} = v_type or p.${p("type")} = '*')${
          tenant
            ? `
        and (p.${p("tenant")} is null or p.${p("tenant")} = v_tenant)`
            : ""
        }
      order by x, c${tenant ? `, p.${p("tenant")} is null` : ""}, p.${p("type")} = '*'
    ) w
    where w.enabled`;
}

function channels(ctx: BlockSqlContext): readonly string[] {
  const list = ctx.list("channels", ["in_app"]);

  for (const channel of list) {
    if (!NAME.test(channel)) {
      throw new TypeError(
        `blocks.notifications.options.channels: "${channel}" is not a channel name`,
      );
    }
  }

  return list;
}

/** `notification_enabled`: the preference order, then the channel default. */
function enabled(ctx: BlockSqlContext, n: NotifyNames): string {
  const id = ctx.idType;
  const fn = ctx.fn("notification_enabled");
  const defaults = channelDefaults(ctx, "notification_enabled.channel");

  const lookup = ctx.hasTable("preferences")
    ? `(
    select p.${n.col("preferences", "enabled")}${notOff(n, "p")}
    from ${n.table("preferences")} p
    where p.${n.col("preferences", "user")} = notification_enabled.member
      and p.${n.col("preferences", "channel")} = notification_enabled.channel
      and (p.${n.col("preferences", "type")} = notification_enabled.type or p.${n.col("preferences", "type")} = '*')${
        n.has("preferences", "tenant")
          ? `
      and (p.${n.col("preferences", "tenant")} is null or p.${n.col("preferences", "tenant")} = notification_enabled.tenant)
    order by p.${n.col("preferences", "tenant")} is null, p.${n.col("preferences", "type")} = '*'`
          : `
    order by p.${n.col("preferences", "type")} = '*'`
      }
    limit 1
  )`
    : "null::boolean";

  return `
-- A member's choice for a type on a channel: the tenant's exact type, the
-- tenant's '*', the exact type anywhere, '*' anywhere, then the channel default.
create or replace function ${fn}(member uuid, tenant ${id}, type text, channel text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(${lookup}, ${defaults})
$$;
revoke execute on function ${fn}(uuid, ${id}, text, text) from public, anon, authenticated;
grant execute on function ${fn}(uuid, ${id}, text, text) to service_role;`;
}

/**
 * Rejects `actions` that aren't an array of at most 10 `{ key, label,
 * operation?, payload? }` objects with unique keys.
 */
function actionsCheck(n: NotifyNames): string {
  if (!n.has("events", "actions")) {
    return "";
  }

  return `
  if notification ? 'actions' and jsonb_typeof(notification -> 'actions') <> 'null' and (
    jsonb_typeof(notification -> 'actions') <> 'array'
    or jsonb_array_length(notification -> 'actions') > 10
    or exists (
      select 1 from jsonb_array_elements(notification -> 'actions') a
      where jsonb_typeof(a) <> 'object'
        or jsonb_typeof(a -> 'key') is distinct from 'string'
        or (a ->> 'key') !~ '^[A-Za-z0-9_.:-]{1,64}$'
        or jsonb_typeof(a -> 'label') is distinct from 'string'
        or length(a ->> 'label') not between 1 and 100
        or (a ? 'operation' and jsonb_typeof(a -> 'operation') <> 'null' and (jsonb_typeof(a -> 'operation') <> 'string' or length(a ->> 'operation') not between 1 and 200))
        or (a ? 'payload' and jsonb_typeof(a -> 'payload') not in ('object', 'null'))
        or exists (select 1 from jsonb_object_keys(a) k where k not in ('key', 'label', 'operation', 'payload'))
    )
    or (select count(distinct a ->> 'key') from jsonb_array_elements(notification -> 'actions') a) <> jsonb_array_length(notification -> 'actions')
  ) then
    ${fail("NOTIFICATION_ACTIONS_INVALID", "actions must be at most 10 { key, label, operation, payload } objects with unique keys", "22023")}
  end if;`;
}

function notify(
  ctx: BlockSqlContext,
  n: NotifyNames,
  layout: BlockSqlLayout = {},
): string {
  const id = ctx.idType;
  const access = ctx.installed("permissions");
  const e = (logical: string) => n.col("events", logical);
  const r = (logical: string) => n.col("recipients", logical);

  const subjects =
    n.has("events", "subjectType") && n.has("events", "subjectId");

  const priorities = ctx.list("priorities", [
    "low",
    "normal",
    "high",
    "urgent",
  ]);

  const defaultChannels = `array[${channels(ctx).map(sqlString).join(", ")}]::text[]`;
  const maxRecipients = ctx.number("maxRecipients", 1000);

  if (!Number.isInteger(maxRecipients) || maxRecipients < 1) {
    throw new TypeError(
      "blocks.notifications.options.maxRecipients must be a whole number above zero",
    );
  }

  const columns: [string, string][] = [
    [e("type"), "v_type"],
    [e("data"), "coalesce(notification -> 'data', '{}')"],
  ];

  const optional: [string, string][] = [
    ["tenant", "v_tenant"],
    ["actor", "v_actor"],
    ["subjectType", "v_subject_type"],
    ["subjectId", "v_subject_id"],
    ["subjectLabel", "notification ->> 'subject_label'"],
    ["summary", "notification ->> 'summary'"],
    ["actionPath", "notification ->> 'action_path'"],
    ["actions", "nullif(notification -> 'actions', 'null'::jsonb)"],
    ["priority", "v_priority"],
    ["key", "v_key"],
    ["createdBy", "auth.uid()"],
  ];

  for (const [logical, value] of optional) {
    if (n.has("events", logical)) {
      columns.push([e(logical), value]);
    }
  }

  const sameTenant = n.has("events", "tenant")
    ? ` and ev.${e("tenant")} is not distinct from v_tenant`
    : "";

  const keyed = n.has("events", "key")
    ? `
  if v_key is not null then
    select ev.${e("id")} into v_event from ${n.table("events")} ev
    where ev.${e("key")} = v_key${sameTenant};
  end if;
  if v_event is null then
    insert into ${n.table("events")} (${columns.map(([column]) => column).join(", ")})
    values (${columns.map(([, value]) => value).join(", ")})
    on conflict do nothing
    returning ${e("id")} into v_event;
  end if;
  if v_event is null then
    select ev.${e("id")} into v_event from ${n.table("events")} ev
    where ev.${e("key")} = v_key${sameTenant};
  end if;`
    : `
  -- Without a key column, a keyed event gets an id derived from the key.
  if v_key is null then
    v_event := gen_random_uuid();
  else
    v_hash := md5(coalesce(v_tenant::text, '') || ':' || v_key);
    select ev.${e("id")} into v_event from ${n.table("events")} ev where ev.${e("id")} = v_hash::uuid;
    v_event := coalesce(v_event, overlay(overlay(v_hash placing '8' from 13 for 1) placing to_hex(8 | (('x' || substr(v_hash, 17, 1))::bit(4)::integer & 3)) from 17 for 1)::uuid);
  end if;
  insert into ${n.table("events")} (${[e("id"), ...columns.map(([column]) => column)].join(", ")})
  values (${["v_event", ...columns.map(([, value]) => value)].join(", ")})
  on conflict do nothing;`;

  const subs = ctx.hasTable("subscriptions") && subjects;
  const s = (logical: string) => n.col("subscriptions", logical);

  const subTenant = n.has("subscriptions", "tenant")
    ? ` and s.${s("tenant")} is not distinct from v_tenant`
    : "";

  const watchers = subs
    ? `
  if v_subject_type is not null and v_subject_id is not null then
    -- watchers: false sends to the named recipients only; ignore still holds.
    if coalesce((notification ->> 'watchers')::boolean, true) then
      v_recipients := v_recipients || array(
        select s.${s("user")} from ${n.table("subscriptions")} s
        where s.${s("subjectType")} = v_subject_type and s.${s("subjectId")} = v_subject_id${subTenant}
          and (s.${s("level")} = 'all' or (v_activity = 'participating' and s.${s("level")} = 'participating'))
      );
    end if;
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not exists (
        select 1 from ${n.table("subscriptions")} s
        where s.${s("subjectType")} = v_subject_type and s.${s("subjectId")} = v_subject_id${subTenant}
          and s.${s("level")} = 'ignore' and s.${s("user")} = x
      )
    );
  end if;`
    : "";

  const readFilter = n.answersForOthers
    ? `
  if v_tenant is not null then
    v_recipients := array(
      select x from unnest(v_recipients) x
      where coalesce(better_supabase.member_can(x, v_tenant, ${n.readPermission}), false)
    );
  end if;`
    : `
  -- The provider model answers for the caller only, so recipients are not
  -- filtered by their read permission: the sender and notification_audience
  -- decide who gets it.`;

  const members = access ? readFilter : "";

  const authorize = access
    ? `
  if not (${SERVICE_CALLER}) then
    if v_tenant is null or not coalesce(better_supabase.member_can(auth.uid(), v_tenant, ${n.sendPermission}), false) then
      ${fail("NOTIFICATION_FORBIDDEN", "Not allowed to send notifications here")}
    end if;
    v_actor := auth.uid();
  end if;`
    : "";

  const audience = ctx.hookTarget("notification_audience");

  const recipientColumns = [
    r("event"),
    ...(n.has("recipients", "tenant") ? [r("tenant")] : []),
    r("user"),
    r("dismissedAt"),
    ...(n.has("recipients", "resolvedAt") ? [r("resolvedAt")] : []),
    r("createdAt"),
  ];

  const recipientValues = [
    "v_event",
    ...(n.has("recipients", "tenant") ? ["v_tenant"] : []),
    "x",
    "case when exists (select 1 from unnest(v_want_members, v_want_channels) w(member, channel) where w.member = x and w.channel = 'in_app') then null else now() end",
    ...(n.has("recipients", "resolvedAt")
      ? [
          "case when coalesce((notification ->> 'resolved')::boolean, false) then now() end",
        ]
      : []),
    // Keeps newest-first order and paging stable within one transaction.
    "clock_timestamp()",
  ];

  const d = (logical: string) => n.col("deliveries", logical);

  const deliveries = ctx.hasTable("deliveries")
    ? `
  insert into ${n.table("deliveries")} (${[
    d("recipient"),
    ...(n.has("deliveries", "tenant") ? [d("tenant")] : []),
    d("channel"),
    d("status"),
    ...(n.has("deliveries", "deliveredAt") ? [d("deliveredAt")] : []),
  ].join(", ")})
  select ${[
    `rc.${r("id")}`,
    ...(n.has("deliveries", "tenant") ? ["v_tenant"] : []),
    "c",
    `case when c = 'in_app' then 'sent' else ${heldStatus(ctx, n, `rc.${r("user")}`)} end`,
    ...(n.has("deliveries", "deliveredAt")
      ? ["case when c = 'in_app' then now() end"]
      : []),
  ].join(", ")}
  from ${n.table("recipients")} rc
  join unnest(v_want_members, v_want_channels) w(member, c) on w.member = rc.${r("user")}
  where rc.${r("event")} = v_event
  on conflict do nothing;`
    : "";

  return `
-- Sends one notification: the event once (per key), a recipient row per
-- member who wants it on some channel, and a delivery per enabled channel.
-- Clients can't insert notifications; they call this, which checks the send
-- permission and records them as the actor.
create or replace function ${ctx.fn("send_notification")}(notification jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := notification ->> 'type';
  v_tenant ${id} := nullif(notification ->> 'tenant', '')::${id};
  v_actor uuid := coalesce(nullif(notification ->> 'actor', '')::uuid, auth.uid());
  v_subject_type text := notification ->> 'subject_type';
  v_subject_id text := notification ->> 'subject_id';
  v_priority text := coalesce(notification ->> 'priority', 'normal');
  v_key text := nullif(notification ->> 'key', '');
  v_activity text := coalesce(notification ->> 'activity', 'participating');
  v_channels text[] := case
    when jsonb_typeof(notification -> 'channels') = 'array'
      then array(select jsonb_array_elements_text(notification -> 'channels'))
    else ${defaultChannels}
  end;
  v_recipients uuid[] := array(
    select x::uuid from jsonb_array_elements_text(coalesce(notification -> 'recipients', '[]')) x
  );
  v_extra uuid[];
  v_event uuid;${n.has("events", "key") ? "" : "\n  v_hash text;"}
  v_want_members uuid[];
  v_want_channels text[];
begin
  if v_type is null or btrim(v_type) = '' then
    ${fail("NOTIFICATION_TYPE_REQUIRED", "A notification needs a type", "22023")}
  end if;
  if not (v_priority = any(array[${priorities.map(sqlString).join(", ")}]::text[])) then
    ${fail("NOTIFICATION_PRIORITY_UNKNOWN", "Unknown notification priority", "22023")}
  end if;
  if v_activity not in ('participating', 'all') then
    ${fail("NOTIFICATION_ACTIVITY_UNKNOWN", "activity must be participating or all", "22023")}
  end if;${actionsCheck(n)}${authorize}
  ${ctx.hook("before_notification_send", [["jsonb", "notification"]])}${consentGate(ctx)}
  if to_regprocedure(${sqlString(`${audience}(jsonb)`)}) is not null then
    execute format('select %s($1)', to_regprocedure(${sqlString(`${audience}(jsonb)`)})::oid::regproc) into v_extra using notification;
    v_recipients := v_recipients || coalesce(v_extra, '{}');
  end if;${watchers}
  ${permissionAudience(ctx, layout)}
  -- exclude: users the composer already reached (the mentioned ones, say).
  if jsonb_typeof(notification -> 'exclude') = 'array' then
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not x = any (array(select e::uuid from jsonb_array_elements_text(notification -> 'exclude') e))
    );
  end if;
  if v_actor is not null and not coalesce((notification ->> 'include_actor')::boolean, false) then
    v_recipients := array_remove(v_recipients, v_actor);
  end if;${members}
  v_recipients := array(select distinct x from unnest(v_recipients) x where x is not null);
  if cardinality(v_recipients) > ${String(maxRecipients)} then
    ${fail("NOTIFICATION_TOO_MANY_RECIPIENTS", `A notification reaches at most ${String(maxRecipients)} recipients`, "22023")}
  end if;
  select coalesce(array_agg(w.member), '{}'), coalesce(array_agg(w.channel), '{}')
  into v_want_members, v_want_channels
  from (
    ${wanted(ctx, n)}
  ) w;
  v_recipients := array(select distinct x from unnest(v_want_members) x);
  if cardinality(v_recipients) = 0 then
    return null;
  end if;
${keyed}${writeExtraColumns(n.table("events"), n.extras, "(notification -> 'fields')", `x.${e("id")} = v_event`)}

  insert into ${n.table("recipients")} (${recipientColumns.join(", ")})
  select ${recipientValues.join(", ")}
  from unnest(v_recipients) x
  on conflict do nothing;${deliveries}
  ${ctx.hook("after_notify", [["uuid", "v_event"]])}
  ${ctx.record({
    type: "notification.created",
    payload:
      "jsonb_build_object('notificationId', v_event, 'organizationId', v_tenant::text, 'type', v_type, 'recipientIds', to_jsonb(v_recipients))",
    subject: "'notifications/' || v_event::text",
    tenant: "v_tenant",
    key: "'notification.created:' || v_event::text",
    audit: false,
  })}
  return jsonb_build_object('id', v_event, 'recipients', to_jsonb(v_recipients));
end;
$$;

create or replace function ${ctx.fn("notify")}(notification jsonb)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select (${ctx.fn("send_notification")}(notification) ->> 'id')::uuid
$$;
-- send_notification for a batch in one call (the outbox sink): each
-- element is one notification, keeps its checks and returns
-- {"notification"} (null when nobody was left) or {"error"} in order.
${batchFunction({
  name: ctx.fn("send_notifications"),
  call: ctx.fn("send_notification"),
  args: "notification",
  returns: "jsonb",
  result: "notification",
  hint: "NOTIFICATION_BATCH",
})}
${["send_notification", "notify", "send_notifications"]
  .map(
    (
      name,
    ) => `revoke execute on function ${ctx.fn(name)}(jsonb) from public, anon${access ? "" : ", authenticated"};
grant execute on function ${ctx.fn(name)}(jsonb) to ${access ? "authenticated, " : ""}service_role;`,
  )
  .join("\n")}`;
}

function inbox(ctx: BlockSqlContext, n: NotifyNames): string {
  const id = ctx.idType;
  const e = (logical: string) => n.col("events", logical);
  const r = (logical: string) => n.col("recipients", logical);

  const tenantFilter = (fn: string, alias = "rc") =>
    n.has("recipients", "tenant")
      ? `and (${fn}.tenant is null or ${alias}.${r("tenant")} = ${fn}.tenant)`
      : "";

  const resolved = n.has("recipients", "resolvedAt");
  const subjectType = n.has("events", "subjectType");
  const subjects = subjectType && n.has("events", "subjectId");

  const settled = resolved
    ? `(rc.${r("resolvedAt")} is not null or rc.${r("dismissedAt")} is not null)`
    : `rc.${r("dismissedAt")} is not null`;

  const haystack = (["summary", "subjectLabel"] as const)
    .filter((logical) => n.has("events", logical))
    .map((logical) => `ev.${e(logical)}`);

  // The inbox reads build their where clause from the filters that are passed,
  // so the planner sees `user = $1 and dismissed_at is null` and can use the
  // partial inbox index. A static "$1 is null or" form is planned once for all
  // values and sorts the whole inbox. Positions in the `using` list: 1 user,
  // 2 tenant, 3 types, 4 subject types, 5 search pattern, 6 read, 7 resolved,
  // 8 dismissed, 9 before, 10 before id.
  const dynamicWhere = (fn: string, cursor: boolean) => {
    const hasTenant = n.has("recipients", "tenant");

    const haystackSql = [...haystack, `ev.${e("type")}`].join(", ");

    return `  v_where := $q$rc.${r("user")} = $1$q$;
  if coalesce(${fn}.status, 'all') = 'settled' then
    v_where := v_where || $q$ and ${settled}$q$;
  elsif ${fn}.dismissed is not null then
    v_where := v_where || case when ${fn}.dismissed
      then $q$ and rc.${r("dismissedAt")} is not null$q$
      else $q$ and rc.${r("dismissedAt")} is null$q$ end;
  end if;
  if ${fn}.read is not null then
    v_where := v_where || case when ${fn}.read
      then $q$ and rc.${r("readAt")} is not null$q$
      else $q$ and rc.${r("readAt")} is null$q$ end;
  end if;
  if ${fn}.resolved is not null then
    v_where := v_where || ${
      resolved
        ? `case when ${fn}.resolved
      then $q$ and rc.${r("resolvedAt")} is not null$q$
      else $q$ and rc.${r("resolvedAt")} is null$q$ end`
        : `case when ${fn}.resolved then $q$ and false$q$ else '' end`
    };
  end if;${
    hasTenant
      ? `
  if ${fn}.tenant is not null then
    v_where := v_where || $q$ and rc.${r("tenant")} = $2$q$;
  end if;`
      : ""
  }
  if ${fn}.types is not null then
    v_where := v_where || $q$ and ev.${e("type")} = any($3)$q$;
  end if;${
    subjectType
      ? `
  if ${fn}.subject_types is not null then
    v_where := v_where || $q$ and ev.${e("subjectType")} = any($4)$q$;
  end if;`
      : ""
  }
  if btrim(coalesce(${fn}.search, '')) <> '' then
    v_where := v_where || $q$ and concat_ws(' ', ${haystackSql}) ilike $5$q$;
  end if;
  case coalesce(${fn}.status, 'all')
    when 'unread' then v_where := v_where || $q$ and rc.${r("readAt")} is null$q$;
    when 'read' then v_where := v_where || $q$ and rc.${r("readAt")} is not null$q$;${
      resolved
        ? `
    when 'unresolved' then v_where := v_where || $q$ and rc.${r("resolvedAt")} is null$q$;`
        : ""
    }
    else null;
  end case;${
    cursor
      ? `
  if ${fn}.before is not null then
    v_where := v_where || $q$ and (rc.${r("createdAt")}, rc.${r("id")}) < ($9, $10)$q$;
  end if;`
      : ""
  }`;
  };

  const searchPattern = (fn: string) =>
    `case when btrim(coalesce(${fn}.search, '')) = '' then null else '%' || replace(replace(replace(btrim(${fn}.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%' end`;

  const isActionable = `${resolved ? `rc.${r("resolvedAt")} is null and ` : ""}ev.${e("type")} = any(coalesce(notification_counts.actionable, '{}'))`;

  const subjectKey = subjects
    ? `case when ev.${e("subjectType")} is not null and ev.${e("subjectId")} is not null then jsonb_build_array(${n.has("events", "tenant") ? `ev.${e("tenant")}, ` : ""}ev.${e("subjectType")}, ev.${e("subjectId")})::text else rc.${r("id")}::text end`
    : `rc.${r("id")}::text`;

  const parts = [
    `
drop function if exists ${ctx.fn("list_notifications")}(${id}, text, text[], timestamptz, integer);
drop function if exists ${ctx.fn("list_notifications")}(${id}, text, text[], timestamptz, integer, uuid);
drop function if exists ${ctx.fn("list_notifications")}(${id}, text, text[], timestamptz, integer, uuid, text[], text);
drop function if exists ${ctx.fn("notification_page")}(${id}, text, text[], text[], text, integer, integer);
drop function if exists ${ctx.fn("notification_page")}(${id}, text, text[], text[], text, integer, integer, boolean, boolean, boolean);
drop function if exists ${ctx.fn("notification_counts")}(${id}, text[]);
${integerMutations(ctx)}
-- The signed-in user's notifications, newest first, without dismissed ones.
-- status: all, unread, read${resolved ? " or unresolved" : ""}. Page with the last item's
-- created_at and id (before, before_id).
create or replace function ${ctx.fn("list_notifications")}(
  tenant ${id} default null,
  status text default 'all',
  types text[] default null,
  before timestamptz default null,
  max_items integer default 50,
  before_id uuid default null,
  subject_types text[] default null,
  search text default null,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_where text;
  result jsonb;
begin
${dynamicWhere("list_notifications", true)}
  execute $q$select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
  from (
    select ${itemJson(n)} as item, rc.${r("createdAt")} as created_at, rc.${r("id")} as id
    from ${n.table("recipients")} rc
    join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}
    where $q$ || v_where || $q$
    order by rc.${r("createdAt")} desc, rc.${r("id")} desc
    limit $11
  ) x$q$
  into result
  using auth.uid(), list_notifications.tenant, list_notifications.types, list_notifications.subject_types,
    ${searchPattern("list_notifications")}, list_notifications.read, list_notifications.resolved, list_notifications.dismissed,
    list_notifications.before, coalesce(list_notifications.before_id, '00000000-0000-0000-0000-000000000000'::uuid),
    least(coalesce(list_notifications.max_items, 50), 200);
  return result;
end;
$$;

create or replace function ${ctx.fn("notification_page")}(
  tenant ${id} default null,
  status text default 'all',
  types text[] default null,
  subject_types text[] default null,
  search text default null,
  max_items integer default 50,
  skip integer default 0,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false,
  before timestamptz default null,
  before_id uuid default null,
  total_cap integer default 10000
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_where text;
  v_limit integer := ${pageSize("notification_page.max_items", 50, 200)};
  v_items jsonb;
  v_total bigint;
  v_args_cap integer := notification_page.total_cap;
begin
${dynamicWhere("notification_page", true)}
  -- One row more than the page says whether an older page exists, and the
  -- total stops counting at total_cap (null counts every row), so a large
  -- inbox never counts all of it. Pass before and before_id to page by key
  -- instead of skip.
  execute $q$select coalesce(jsonb_agg(p.item order by p.created_at desc, p.id desc), '[]')
  from (
    select ${itemJson(n)} as item, rc.${r("createdAt")} as created_at, rc.${r("id")} as id
    from ${n.table("recipients")} rc
    join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}
    where $q$ || v_where || $q$
    order by rc.${r("createdAt")} desc, rc.${r("id")} desc
    offset $11
    limit $12 + 1
  ) p$q$
  into v_items
  using auth.uid(), notification_page.tenant, notification_page.types, notification_page.subject_types,
    ${searchPattern("notification_page")}, notification_page.read, notification_page.resolved, notification_page.dismissed,
    notification_page.before, coalesce(notification_page.before_id, '00000000-0000-0000-0000-000000000000'::uuid),
    greatest(coalesce(notification_page.skip, 0), 0), v_limit;
  execute $q$select count(*) from (
    select 1 from ${n.table("recipients")} rc
    join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}
    where $q$ || v_where || case when v_args_cap is null then '' else format(' limit %s', greatest(v_args_cap, 1)) end || $q$
  ) c$q$
  into v_total
  using auth.uid(), notification_page.tenant, notification_page.types, notification_page.subject_types,
    ${searchPattern("notification_page")}, notification_page.read, notification_page.resolved, notification_page.dismissed,
    notification_page.before, coalesce(notification_page.before_id, '00000000-0000-0000-0000-000000000000'::uuid);
  return jsonb_build_object(
    'items', coalesce((select jsonb_agg(x.value order by x.ordinality) from jsonb_array_elements(v_items) with ordinality x(value, ordinality) where x.ordinality <= v_limit), '[]'),
    'hasMore', jsonb_array_length(v_items) > v_limit,
    'total', v_total,
    'totalCapped', v_args_cap is not null and v_total >= v_args_cap
  );
end;
$$;

-- Unread and, for the types in actionable, unresolved counts. Each count stops
-- at cap (default 100, null counts every row), so a badge reads at most cap
-- rows through the unread index however large the inbox is.
create or replace function ${ctx.fn("notification_counts")}(tenant ${id} default null, actionable text[] default null, cap integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'unread', (
      select count(*) from (
        select 1 from ${n.table("recipients")} rc
        where rc.${r("user")} = auth.uid()
          and rc.${r("readAt")} is null
          and rc.${r("dismissedAt")} is null
          ${tenantFilter("notification_counts")}
        limit notification_counts.cap
      ) u
    ),
    'actionable', ${resolved ? "coalesce(act.rows, 0)" : "0"},
    'actionable_subjects', ${resolved ? "coalesce(act.subjects, 0)" : "0"}
  )
  from (select 1) one${
    resolved
      ? `
  left join lateral (
    select count(*) as rows, count(distinct a.subject_key) as subjects
    from (
      select ${subjectKey} as subject_key
      from ${n.table("recipients")} rc
      join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}
      where cardinality(coalesce(notification_counts.actionable, '{}')) > 0
        and rc.${r("user")} = auth.uid()
        and rc.${r("dismissedAt")} is null
        and ${isActionable}
        ${tenantFilter("notification_counts")}
      limit notification_counts.cap
    ) a
  ) act on true`
      : ""
  }
$$;

create or replace function ${ctx.fn("get_notification")}(id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${itemJson(n)}
  from ${n.table("recipients")} rc
  join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}
  where rc.${r("id")} = get_notification.id
    and rc.${r("user")} = auth.uid()
$$;

create or replace function ${ctx.fn("mark_notifications_unread")}(ids uuid[], tenant ${id} default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  with rc as (
    update ${n.table("recipients")} rc set ${r("readAt")} = null
    where rc.${r("user")} = auth.uid()
      and rc.${r("readAt")} is not null
      and rc.${r("dismissedAt")} is null
      and rc.${r("id")} = any(mark_notifications_unread.ids)
      ${tenantFilter("mark_notifications_unread")}
    returning rc.*
  )
  ${changedJson(n)}
$$;

create or replace function ${ctx.fn("mark_notifications_read")}(ids uuid[] default null, tenant ${id} default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  with rc as (
    update ${n.table("recipients")} rc set ${r("readAt")} = now()
    where rc.${r("user")} = auth.uid()
      and rc.${r("readAt")} is null
      and rc.${r("dismissedAt")} is null
      and rc.${r("id")} in (
        select picked from unnest(mark_notifications_read.ids) picked
        union all
        select all_rc.${r("id")} from ${n.table("recipients")} all_rc
        where mark_notifications_read.ids is null and all_rc.${r("user")} = auth.uid() and all_rc.${r("readAt")} is null
      )
      ${tenantFilter("mark_notifications_read")}
    returning rc.*
  )
  ${changedJson(n)}
$$;

create or replace function ${ctx.fn("dismiss_notifications")}(ids uuid[])
returns jsonb
language sql
security definer
set search_path = ''
as $$
  with rc as (
    update ${n.table("recipients")} rc
    set ${r("dismissedAt")} = now(), ${r("readAt")} = coalesce(rc.${r("readAt")}, now())
    where rc.${r("user")} = auth.uid()
      and rc.${r("dismissedAt")} is null
      and rc.${r("id")} = any(dismiss_notifications.ids)
    returning rc.*
  )
  ${changedJson(n)}
$$;`,
  ];

  const grants = [
    `list_notifications(${id}, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean)`,
    `notification_page(${id}, text, text[], text[], text, integer, integer, boolean, boolean, boolean, timestamptz, uuid, integer)`,
    `notification_counts(${id}, text[], integer)`,
    `mark_notifications_unread(uuid[], ${id})`,
    `mark_notifications_read(uuid[], ${id})`,
    "dismiss_notifications(uuid[])",
    "get_notification(uuid)",
  ];

  if (
    resolved &&
    n.has("events", "subjectType") &&
    n.has("events", "subjectId")
  ) {
    const resolution = n.has("recipients", "resolution");

    const tenantMatch = n.has("events", "tenant")
      ? `and ev.${e("tenant")} is not distinct from resolve_notifications.tenant`
      : "";

    const allowed = ctx.installed("permissions")
      ? `(${SERVICE_CALLER}) or coalesce(better_supabase.member_can(auth.uid(), resolve_notifications.tenant, ${n.sendPermission}), false)`
      : SERVICE_CALLER;

    parts.push(`
-- Marks every recipient's notification of this type about this subject
-- resolved (and read), e.g. once the approval it asked for is given.${
      resolution
        ? `
-- resolution records how, e.g. {"action": "approve"}.
drop function if exists ${ctx.fn("resolve_notifications")}(text, text, text, ${id});`
        : ""
    }
create or replace function ${ctx.fn("resolve_notifications")}(type text, subject_type text, subject_id text, tenant ${id} default null${resolution ? ", resolution jsonb default null" : ""})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_changed jsonb;
begin
  if not (${allowed}) then
    ${fail("NOTIFICATION_FORBIDDEN", "Not allowed to resolve notifications here")}
  end if;${
    resolution
      ? `
  if resolve_notifications.resolution is not null and jsonb_typeof(resolve_notifications.resolution) <> 'object' then
    ${fail("NOTIFICATION_RESOLUTION_INVALID", "resolution must be a JSON object", "22023")}
  end if;`
      : ""
  }
  with rc as (
    update ${n.table("recipients")} rc
    set ${r("resolvedAt")} = now(), ${r("readAt")} = coalesce(rc.${r("readAt")}, now())${resolution ? `, ${r("resolution")} = resolve_notifications.resolution` : ""}
    from ${n.table("events")} ev
    where ev.${e("id")} = rc.${r("event")}
      and ev.${e("type")} = resolve_notifications.type
      and ev.${e("subjectType")} = resolve_notifications.subject_type
      and ev.${e("subjectId")} = resolve_notifications.subject_id
      ${tenantMatch}
      and rc.${r("resolvedAt")} is null
      and rc.${r("dismissedAt")} is null
    returning rc.*
  )
  ${changedJson(n)} into v_changed;
  return v_changed;
end;
$$;`);
    grants.push(
      `resolve_notifications(text, text, text, ${id}${resolution ? ", jsonb" : ""})`,
    );
  }

  if (ctx.installed("profiles") && n.has("events", "actor")) {
    const profiles = ctx.of("profiles");
    const p = (logical: string) => profiles.col("profiles", logical);

    const fields = (
      [
        ["username", "username"],
        ["fullName", "fullName"],
        ["firstName", "firstName"],
        ["lastName", "lastName"],
        ["avatar", "avatar"],
        ["avatarPath", "avatarPath"],
      ] as const
    )
      .filter(([logical]) =>
        logical === "avatarPath"
          ? hasAvatarPath(profiles)
          : profiles.has("profiles", logical),
      )
      .map(([key, logical]) => `, '${key}', pr.${p(logical)}`)
      .join("");

    parts.push(`
-- The public profile fields of the actors behind the caller's notifications,
-- keyed by user id, for list({ include: ['actor'] }). Only actors of the
-- caller's own notifications.
create or replace function ${ctx.fn("notification_actors")}(ids uuid[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(pr.${p("key")}::text, jsonb_build_object('id', pr.${p("key")}${fields})), '{}')
  from ${profiles.table("profiles")} pr
  where pr.${p("key")} = any(notification_actors.ids)
    and exists (
      select 1 from ${n.table("recipients")} rc
      join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}
      where rc.${r("user")} = auth.uid() and ev.${e("actor")} = pr.${p("key")}
    )
$$;`);
    grants.push("notification_actors(uuid[])");
  }

  for (const signature of grants) {
    parts.push(`revoke execute on function ${ctx.schema}.${signature} from public, anon;
grant execute on function ${ctx.schema}.${signature} to authenticated, service_role;`);
  }

  return parts.join("\n");
}

/** `set_notification_subscription` and `set_notification_preference`. */
function settings(ctx: BlockSqlContext, n: NotifyNames): string {
  const id = ctx.idType;
  const parts: string[] = [];

  const member = (fn: string) =>
    ctx.installed("permissions")
      ? `
  if ${fn}.tenant is not null and not (${SERVICE_CALLER})
    and not coalesce(better_supabase.member_can(auth.uid(), ${fn}.tenant, ${n.readPermission}), false) then
    ${fail("NOTIFICATION_FORBIDDEN", "Not a member of this organization")}
  end if;`
      : "";

  if (ctx.hasTable("subscriptions")) {
    const s = (logical: string) => n.col("subscriptions", logical);
    const t = n.has("subscriptions", "tenant");
    const fn = "set_notification_subscription";
    parts.push(`
-- Watches (all), follows (participating) or ignores a subject; a null level
-- removes the choice. The service can set it for another member. With
-- if_absent it only adds a level for a member without one, and then a
-- sender (the send permission in the tenant) may set it for another member,
-- to make the author or an assignee follow without overriding their choice.
drop function if exists ${ctx.fn(fn)}(text, text, text, ${id}, uuid);
create or replace function ${ctx.fn(fn)}(subject_type text, subject_id text, level text, tenant ${id} default null, member uuid default null, if_absent boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(${fn}.member, auth.uid());
begin
  if v_user is distinct from auth.uid() and not (${SERVICE_CALLER})${
    ctx.installed("permissions")
      ? ` and not (
    coalesce(${fn}.if_absent, false) and ${fn}.level is not null and ${fn}.tenant is not null
    and coalesce(better_supabase.member_can(auth.uid(), ${fn}.tenant, ${n.sendPermission}), false)
    and coalesce(better_supabase.member_can(v_user, ${fn}.tenant, ${n.readPermission}), false)
  )`
      : ""
  } then
    ${fail("NOTIFICATION_FORBIDDEN", "Only the service, or a sender with if_absent, sets subscriptions for others")}
  end if;
  if ${fn}.level is not null and ${fn}.level not in ('participating', 'all', 'ignore') then
    ${fail("NOTIFICATION_LEVEL_UNKNOWN", "level must be participating, all or ignore", "22023")}
  end if;${member(fn)}
  if coalesce(${fn}.if_absent, false) then
    if ${fn}.level is not null and not exists (
      select 1 from ${n.table("subscriptions")} s
      where s.${s("user")} = v_user
        and s.${s("subjectType")} = ${fn}.subject_type
        and s.${s("subjectId")} = ${fn}.subject_id${
          t
            ? `
        and s.${s("tenant")} is not distinct from ${fn}.tenant`
            : ""
        }
    ) then
      insert into ${n.table("subscriptions")} (${[...(t ? [s("tenant")] : []), s("user"), s("subjectType"), s("subjectId"), s("level")].join(", ")})
      values (${[...(t ? [`${fn}.tenant`] : []), "v_user", `${fn}.subject_type`, `${fn}.subject_id`, `${fn}.level`].join(", ")});
    end if;
    return;
  end if;
  delete from ${n.table("subscriptions")} s
  where s.${s("user")} = v_user
    and s.${s("subjectType")} = ${fn}.subject_type
    and s.${s("subjectId")} = ${fn}.subject_id${t ? `\n    and s.${s("tenant")} is not distinct from ${fn}.tenant` : ""};
  if ${fn}.level is not null then
    insert into ${n.table("subscriptions")} (${[...(t ? [s("tenant")] : []), s("user"), s("subjectType"), s("subjectId"), s("level")].join(", ")})
    values (${[...(t ? [`${fn}.tenant`] : []), "v_user", `${fn}.subject_type`, `${fn}.subject_id`, `${fn}.level`].join(", ")});
  end if;
end;
$$;
revoke execute on function ${ctx.fn(fn)}(text, text, text, ${id}, uuid, boolean) from public, anon;
grant execute on function ${ctx.fn(fn)}(text, text, text, ${id}, uuid, boolean) to authenticated, service_role;`);
  }

  if (ctx.hasTable("preferences")) {
    const p = (logical: string) => n.col("preferences", logical);
    const t = n.has("preferences", "tenant");
    const fn = "set_notification_preference";
    parts.push(`
-- Turns a type ('*' for all) on or off on a channel, for one organization or
-- everywhere (tenant null); a null enabled removes the choice.
create or replace function ${ctx.fn(fn)}(type text, channel text, enabled boolean, tenant ${id} default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    ${fail("NOTIFICATION_FORBIDDEN", "Sign in to change notification preferences")}
  end if;${member(fn)}
  delete from ${n.table("preferences")} p
  where p.${p("user")} = auth.uid()
    and p.${p("type")} = ${fn}.type
    and p.${p("channel")} = ${fn}.channel${t ? `\n    and p.${p("tenant")} is not distinct from ${fn}.tenant` : ""};
  if ${fn}.enabled is not null then
    insert into ${n.table("preferences")} (${[p("user"), ...(t ? [p("tenant")] : []), p("type"), p("channel"), p("enabled")].join(", ")})
    values (${["auth.uid()", ...(t ? [`${fn}.tenant`] : []), `${fn}.type`, `${fn}.channel`, `${fn}.enabled`].join(", ")});
  end if;
end;
$$;
revoke execute on function ${ctx.fn(fn)}(text, text, boolean, ${id}) from public, anon;
grant execute on function ${ctx.fn(fn)}(text, text, boolean, ${id}) to authenticated, service_role;`);
  }

  return parts.join("\n");
}

export function functions(
  ctx: BlockSqlContext,
  n: NotifyNames,
  layout: BlockSqlLayout = {},
): string {
  return [
    enabled(ctx, n),
    notify(ctx, n, layout),
    inbox(ctx, n),
    settings(ctx, n),
    readers(ctx, n),
    delivery(ctx, n),
    digestFunctions(ctx, n),
    suppressionFunctions(ctx, n),
    trackingFunctions(ctx, n),
    purge(ctx, n),
  ].join("\n");
}
