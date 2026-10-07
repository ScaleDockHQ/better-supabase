import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER } from "../shared.ts";
import { accessModel, MODULE_PERMISSIONS } from "./access-model.ts";

export interface NotifyNames {
  readonly table: (table: string) => string;
  readonly col: (table: string, logical: string) => string;
  readonly has: (table: string, logical: string) => boolean;
  /** SQL literals of the permission keys. */
  readonly sendPermission: string;
  readonly readPermission: string;
  /** Whether `member_can` answers for users other than the caller. */
  readonly answersForOthers: boolean;
}

export function notifyNames(
  ctx: ModuleContext,
  answersForOthers: boolean = accessModel(ctx) !== "permdock",
): NotifyNames {
  return {
    answersForOthers,
    table: (table) => ctx.table(table),
    col: (table, logical) => ctx.col(table, logical),
    has: (table, logical) => ctx.hasTable(table) && ctx.has(table, logical),
    sendPermission: ctx.permission(
      "send",
      MODULE_PERMISSIONS.notifications.send,
    ),
    readPermission: ctx.permission(
      "read",
      MODULE_PERMISSIONS.notifications.read,
    ),
  };
}

const NAME = /^[a-z][a-z0-9_]*$/;

const fail = (code: string, message: string, errcode = "42501"): string =>
  `raise exception '${message}' using errcode = '${errcode}', hint = '${code}';`;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** A channel nobody chose is on for `in_app` and off for the rest, unless `channelDefaults` says otherwise. */
function channelDefaults(ctx: ModuleContext, channel: string): string {
  const value = ctx.option("channelDefaults") ?? {};
  if (!isRecord(value)) {
    throw new TypeError(
      "sql.modules.notifications.options.channelDefaults must map channel names to booleans",
    );
  }
  const cases = Object.entries(value).map(([channel, enabled]) => {
    if (!NAME.test(channel) || typeof enabled !== "boolean") {
      throw new TypeError(
        `sql.modules.notifications.options.channelDefaults.${channel} must be a boolean`,
      );
    }
    return `when ${sqlString(channel)} then ${String(enabled)}`;
  });
  return `case ${channel} ${[...cases, "when 'in_app' then true"].join(" ")} else false end`;
}

/**
 * The (member, channel) pairs that want this notification, in one query:
 * each pair's most specific preference, or the channel default.
 */
function wanted(ctx: ModuleContext, n: NotifyNames): string {
  const defaults = channelDefaults(ctx, "c");
  if (!ctx.hasTable("preferences")) {
    return `select x as member, c as channel
    from unnest(v_recipients) x cross join unnest(v_channels) c
    where ${defaults}`;
  }
  const p = (logical: string) => n.col("preferences", logical);
  const tenant = n.has("preferences", "tenant");
  return `select w.member, w.channel from (
      select distinct on (x, c) x as member, c as channel, coalesce(p.${p("enabled")}, ${defaults}) as enabled
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

function channels(ctx: ModuleContext): readonly string[] {
  const list = ctx.list("channels", ["in_app"]);
  for (const channel of list) {
    if (!NAME.test(channel)) {
      throw new TypeError(
        `sql.modules.notifications.options.channels: "${channel}" is not a channel name`,
      );
    }
  }
  return list;
}

/** `notification_enabled`: the preference order, then the channel default. */
function enabled(ctx: ModuleContext, n: NotifyNames): string {
  const id = ctx.idType;
  const fn = ctx.fn("notification_enabled");
  const defaults = channelDefaults(ctx, "notification_enabled.channel");
  const lookup = ctx.hasTable("preferences")
    ? `(
    select p.${n.col("preferences", "enabled")}
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

function notify(ctx: ModuleContext, n: NotifyNames): string {
  const id = ctx.idType;
  const access = ctx.installed("access");
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
      "sql.modules.notifications.options.maxRecipients must be a whole number above zero",
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
    ["priority", "v_priority"],
    ["key", "v_key"],
    ["createdBy", "auth.uid()"],
  ];
  for (const [logical, value] of optional) {
    if (n.has("events", logical)) columns.push([e(logical), value]);
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
  v_event := case when v_key is null then gen_random_uuid() else md5(coalesce(v_tenant::text, '') || ':' || v_key)::uuid end;
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
  -- The permdock model answers for the caller only, so recipients are not
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
    "case when c = 'in_app' then 'sent' else 'pending' end",
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
create or replace function ${ctx.fn("notify")}(notification jsonb)
returns uuid
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
  v_event uuid;
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
  end if;${authorize}
  if to_regprocedure(${sqlString(`${audience}(jsonb)`)}) is not null then
    execute format('select %s($1)', to_regprocedure(${sqlString(`${audience}(jsonb)`)})::oid::regproc) into v_extra using notification;
    v_recipients := v_recipients || coalesce(v_extra, '{}');
  end if;${watchers}
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
${keyed}

  insert into ${n.table("recipients")} (${recipientColumns.join(", ")})
  select ${recipientValues.join(", ")}
  from unnest(v_recipients) x
  on conflict do nothing;${deliveries}
  ${ctx.hook("after_notify", [["uuid", "v_event"]])}
  ${ctx.emit({
    type: "notification.created",
    payload:
      "jsonb_build_object('notificationId', v_event, 'type', v_type, 'recipientIds', to_jsonb(v_recipients))",
    subject: "'notifications/' || v_event::text",
    tenant: "v_tenant",
  })}
  return v_event;
end;
$$;
revoke execute on function ${ctx.fn("notify")}(jsonb) from public, anon${access ? "" : ", authenticated"};
grant execute on function ${ctx.fn("notify")}(jsonb) to ${access ? "authenticated, " : ""}service_role;`;
}

/** The recipient's view: the event's columns next to its own state. */
function itemJson(n: NotifyNames): string {
  const e = (logical: string) => n.col("events", logical);
  const r = (logical: string) => n.col("recipients", logical);
  const pairs: [string, string][] = [
    ["id", `rc.${r("id")}`],
    ["event_id", `ev.${e("id")}`],
    ["type", `ev.${e("type")}`],
    ["data", `ev.${e("data")}`],
    ["created_at", `rc.${r("createdAt")}`],
    ["read_at", `rc.${r("readAt")}`],
  ];
  const optional: [string, string, string][] = [
    ["tenant", "events", "tenant"],
    ["actor_id", "events", "actor"],
    ["subject_type", "events", "subjectType"],
    ["subject_id", "events", "subjectId"],
    ["subject_label", "events", "subjectLabel"],
    ["summary", "events", "summary"],
    ["action_path", "events", "actionPath"],
    ["priority", "events", "priority"],
    ["resolved_at", "recipients", "resolvedAt"],
  ];
  for (const [key, table, logical] of optional) {
    if (n.has(table, logical)) {
      pairs.push([
        key,
        `${table === "events" ? "ev" : "rc"}.${n.col(table, logical)}`,
      ]);
    }
  }
  return `jsonb_build_object(${pairs.map(([key, value]) => `'${key}', ${value}`).join(", ")})`;
}

function inbox(ctx: ModuleContext, n: NotifyNames): string {
  const id = ctx.idType;
  const e = (logical: string) => n.col("events", logical);
  const r = (logical: string) => n.col("recipients", logical);
  const tenantFilter = (fn: string, alias = "rc") =>
    n.has("recipients", "tenant")
      ? `and (${fn}.tenant is null or ${alias}.${r("tenant")} = ${fn}.tenant)`
      : "";
  const resolved = n.has("recipients", "resolvedAt");
  const unresolvedStatus = resolved
    ? `
        when 'unresolved' then rc.${r("resolvedAt")} is null`
    : "";
  const actionable = resolved
    ? `count(*) filter (
      where rc.${r("resolvedAt")} is null and ev.${e("type")} = any(coalesce(notification_counts.actionable, '{}'))
    )`
    : "0";
  const parts = [
    `
drop function if exists ${ctx.fn("list_notifications")}(${id}, text, text[], timestamptz, integer);
-- The signed-in user's notifications, newest first, without dismissed ones.
-- status: all, unread, read${resolved ? " or unresolved" : ""}. Page with the last item's
-- created_at and id (before, before_id).
create or replace function ${ctx.fn("list_notifications")}(
  tenant ${id} default null,
  status text default 'all',
  types text[] default null,
  before timestamptz default null,
  max_items integer default 50,
  before_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
  from (
    select ${itemJson(n)} as item, rc.${r("createdAt")} as created_at, rc.${r("id")} as id
    from ${n.table("recipients")} rc
    join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}
    where rc.${r("user")} = auth.uid()
      and rc.${r("dismissedAt")} is null
      ${tenantFilter("list_notifications")}
      and (list_notifications.types is null or ev.${e("type")} = any(list_notifications.types))
      and (
        list_notifications.before is null
        or (rc.${r("createdAt")}, rc.${r("id")}) < (list_notifications.before, coalesce(list_notifications.before_id, '00000000-0000-0000-0000-000000000000'::uuid))
      )
      and case coalesce(list_notifications.status, 'all')
        when 'unread' then rc.${r("readAt")} is null
        when 'read' then rc.${r("readAt")} is not null${unresolvedStatus}
        else true
      end
    order by rc.${r("createdAt")} desc, rc.${r("id")} desc
    limit least(coalesce(list_notifications.max_items, 50), 200)
  ) x
$$;

-- Unread and, for the types in actionable, unresolved counts.
create or replace function ${ctx.fn("notification_counts")}(tenant ${id} default null, actionable text[] default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'unread', count(*) filter (where rc.${r("readAt")} is null),
    'actionable', ${actionable}
  )
  from ${n.table("recipients")} rc
  join ${n.table("events")} ev on ev.${e("id")} = rc.${r("event")}
  where rc.${r("user")} = auth.uid()
    and rc.${r("dismissedAt")} is null
    ${tenantFilter("notification_counts")}
$$;

-- Marks the given notifications, or all of them, read. Returns how many changed.
create or replace function ${ctx.fn("mark_notifications_read")}(ids uuid[] default null, tenant ${id} default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed integer;
begin
  update ${n.table("recipients")} rc set ${r("readAt")} = now()
  where rc.${r("user")} = auth.uid()
    and rc.${r("readAt")} is null
    and rc.${r("dismissedAt")} is null
    and (mark_notifications_read.ids is null or rc.${r("id")} = any(mark_notifications_read.ids))
    ${tenantFilter("mark_notifications_read")};
  get diagnostics changed = row_count;
  return changed;
end;
$$;

create or replace function ${ctx.fn("dismiss_notifications")}(ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed integer;
begin
  update ${n.table("recipients")} rc
  set ${r("dismissedAt")} = now(), ${r("readAt")} = coalesce(rc.${r("readAt")}, now())
  where rc.${r("user")} = auth.uid()
    and rc.${r("dismissedAt")} is null
    and rc.${r("id")} = any(dismiss_notifications.ids);
  get diagnostics changed = row_count;
  return changed;
end;
$$;`,
  ];
  const grants = [
    `list_notifications(${id}, text, text[], timestamptz, integer, uuid)`,
    `notification_counts(${id}, text[])`,
    `mark_notifications_read(uuid[], ${id})`,
    "dismiss_notifications(uuid[])",
  ];
  if (
    resolved &&
    n.has("events", "subjectType") &&
    n.has("events", "subjectId")
  ) {
    const tenantMatch = n.has("events", "tenant")
      ? `and ev.${e("tenant")} is not distinct from resolve_notifications.tenant`
      : "";
    const allowed = ctx.installed("access")
      ? `(${SERVICE_CALLER}) or coalesce(better_supabase.member_can(auth.uid(), resolve_notifications.tenant, ${n.sendPermission}), false)`
      : SERVICE_CALLER;
    parts.push(`
-- Marks every recipient's notification of this type about this subject
-- resolved (and read), e.g. once the approval it asked for is given.
create or replace function ${ctx.fn("resolve_notifications")}(type text, subject_type text, subject_id text, tenant ${id} default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed integer;
begin
  if not (${allowed}) then
    ${fail("NOTIFICATION_FORBIDDEN", "Not allowed to resolve notifications here")}
  end if;
  update ${n.table("recipients")} rc
  set ${r("resolvedAt")} = now(), ${r("readAt")} = coalesce(rc.${r("readAt")}, now())
  from ${n.table("events")} ev
  where ev.${e("id")} = rc.${r("event")}
    and ev.${e("type")} = resolve_notifications.type
    and ev.${e("subjectType")} = resolve_notifications.subject_type
    and ev.${e("subjectId")} = resolve_notifications.subject_id
    ${tenantMatch}
    and rc.${r("resolvedAt")} is null
    and rc.${r("dismissedAt")} is null;
  get diagnostics changed = row_count;
  return changed;
end;
$$;`);
    grants.push(`resolve_notifications(text, text, text, ${id})`);
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
      ] as const
    )
      .filter(([logical]) => profiles.has("profiles", logical))
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
function settings(ctx: ModuleContext, n: NotifyNames): string {
  const id = ctx.idType;
  const parts: string[] = [];
  const member = (fn: string) =>
    ctx.installed("access")
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
    ctx.installed("access")
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

/** The worker side: claim pending deliveries of a channel, then complete them. */
function delivery(ctx: ModuleContext, n: NotifyNames): string {
  if (!ctx.hasTable("deliveries")) return "";
  const d = (logical: string) => n.col("deliveries", logical);
  const r = (logical: string) => n.col("recipients", logical);
  const attempts = n.has("deliveries", "attempts")
    ? `, ${d("attempts")} = d.${d("attempts")} + 1`
    : "";
  const set: string[] = [`${d("status")} = v_status`];
  if (n.has("deliveries", "provider"))
    set.push(
      `${d("provider")} = coalesce(complete_notification_delivery.provider, d.${d("provider")})`,
    );
  if (n.has("deliveries", "providerMessageId"))
    set.push(
      `${d("providerMessageId")} = coalesce(complete_notification_delivery.provider_message_id, d.${d("providerMessageId")})`,
    );
  if (n.has("deliveries", "error"))
    set.push(`${d("error")} = complete_notification_delivery.error`);
  if (n.has("deliveries", "deliveredAt"))
    set.push(
      `${d("deliveredAt")} = case when v_status = 'sent' then now() else d.${d("deliveredAt")} end`,
    );
  set.push(
    `${d("attemptedAt")} = case when v_status = 'pending' then null else d.${d("attemptedAt")} end`,
  );
  const retries = n.has("deliveries", "attempts");
  const backoff = n.has("deliveries", "nextAttemptAt");
  if (backoff)
    set.push(
      `${d("nextAttemptAt")} = case when v_status = 'pending' then now() + make_interval(secs => 1 + floor(random() * least(3600, 30 * power(2, ${retries ? `greatest(d.${d("attempts")}, 1) - 1` : "0"})))) else d.${d("nextAttemptAt")} end`,
    );
  const lostLease = retries
    ? `
  -- A delivery whose lease ran out on its last attempt lost its worker.
  update ${n.table("deliveries")} d
  set ${d("status")} = 'failed'${n.has("deliveries", "error") ? `, ${d("error")} = 'The lease ran out on the last attempt'` : ""}
  where d.${d("channel")} = claim_notification_deliveries.channel
    and d.${d("status")} = 'pending'
    and d.${d("attempts")} >= greatest(1, coalesce(claim_notification_deliveries.max_attempts, 5))
    and d.${d("attemptedAt")} < now() - claim_notification_deliveries.lease;
`
    : "";
  const giveUp = retries
    ? `
  if v_status = 'pending' and exists (
    select 1 from ${n.table("deliveries")} d
    where d.${d("id")} = complete_notification_delivery.delivery
      and d.${d("attempts")} >= greatest(1, coalesce(complete_notification_delivery.max_attempts, 5))
  ) then
    v_status := 'failed';
  end if;`
    : "";
  return `
drop function if exists ${ctx.fn("claim_notification_deliveries")}(text, integer, interval);
drop function if exists ${ctx.fn("complete_notification_delivery")}(uuid, text, text, text, text);
-- Leases up to max_items due deliveries of one channel and returns them
-- with the notification and the recipient's email, for a NotificationChannel.
create or replace function ${ctx.fn("claim_notification_deliveries")}(channel text, max_items integer default 50, lease interval default '5 minutes', max_attempts integer default 5)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed jsonb;
begin${lostLease}
  with picked as (
    select d.${d("id")} as id from ${n.table("deliveries")} d
    where d.${d("channel")} = claim_notification_deliveries.channel
      and d.${d("status")} = 'pending'${
        backoff
          ? `
      and d.${d("nextAttemptAt")} <= now()`
          : ""
      }
      and (d.${d("attemptedAt")} is null or d.${d("attemptedAt")} < now() - claim_notification_deliveries.lease)
    order by d.${d("createdAt")}
    limit claim_notification_deliveries.max_items
    for update skip locked
  ), leased as (
    update ${n.table("deliveries")} d set ${d("attemptedAt")} = now()${attempts}
    from picked where d.${d("id")} = picked.id
    returning d.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'delivery_id', l.${d("id")},
    'channel', l.${d("channel")},
    'attempts', ${retries ? `l.${d("attempts")}` : "1"},
    'user_id', rc.${r("user")},
    'email', u.email,
    'notification', ${itemJson(n)}
  )), '[]') into claimed
  from leased l
  join ${n.table("recipients")} rc on rc.${r("id")} = l.${d("recipient")}
  join ${n.table("events")} ev on ev.${n.col("events", "id")} = rc.${r("event")}
  left join auth.users u on u.id = rc.${r("user")};
  return claimed;
end;
$$;

-- Records the outcome: sent, failed, skipped, or pending to retry. A retry
-- waits a random time up to 30 seconds, doubling per attempt to an hour,
-- and after max_attempts the delivery is failed instead.
create or replace function ${ctx.fn("complete_notification_delivery")}(delivery uuid, status text, provider text default null, provider_message_id text default null, error text default null, max_attempts integer default 5)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := complete_notification_delivery.status;
begin
  if v_status is null or v_status not in ('sent', 'failed', 'skipped', 'pending') then
    ${fail("NOTIFICATION_STATUS_UNKNOWN", "status must be sent, failed, skipped or pending", "22023")}
  end if;${giveUp}
  update ${n.table("deliveries")} d
  set ${set.join(",\n    ")}
  where d.${d("id")} = complete_notification_delivery.delivery;
  return v_status;
end;
$$;
revoke execute on function ${ctx.fn("claim_notification_deliveries")}(text, integer, interval, integer) from public, anon, authenticated;
grant execute on function ${ctx.fn("claim_notification_deliveries")}(text, integer, interval, integer) to service_role;
revoke execute on function ${ctx.fn("complete_notification_delivery")}(uuid, text, text, text, text, integer) from public, anon, authenticated;
grant execute on function ${ctx.fn("complete_notification_delivery")}(uuid, text, text, text, text, integer) to service_role;`;
}

/** Deletes up to batch notifications older than older_than, with their recipients and deliveries. */
function purge(ctx: ModuleContext, n: NotifyNames): string {
  const e = (logical: string) => n.col("events", logical);
  const fn = ctx.fn("purge_notifications");
  return `
-- Deletes up to batch notifications older than older_than, with their
-- recipients and deliveries, and returns how many. Run it until it returns
-- less than batch.
create or replace function ${fn}(older_than interval default '90 days', batch integer default 10000)
returns integer
language sql
security definer
set search_path = ''
as $$
  with gone as (
    delete from ${n.table("events")}
    where ${e("id")} in (
      select ev.${e("id")} from ${n.table("events")} ev
      where ev.${e("createdAt")} < now() - coalesce(older_than, '90 days')
      order by ev.${e("createdAt")}
      limit coalesce(batch, 10000)
    )
    returning 1
  )
  select count(*)::integer from gone
$$;
revoke execute on function ${fn}(interval, integer) from public, anon, authenticated;
grant execute on function ${fn}(interval, integer) to service_role;`;
}

export function functions(ctx: ModuleContext, n: NotifyNames): string {
  return [
    enabled(ctx, n),
    notify(ctx, n),
    inbox(ctx, n),
    settings(ctx, n),
    delivery(ctx, n),
    purge(ctx, n),
  ].join("\n");
}
