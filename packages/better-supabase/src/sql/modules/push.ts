import type { PushEvents } from "../../blocks/push/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  raise,
  revokeTable,
  schemaPreamble,
  SERVICE_CALLER,
  writeExtraColumns,
} from "../shared.ts";
import { pushTickets, ticketsContract } from "./push-tickets.ts";

const EVENTS: BlockSqlEvents<PushEvents> = {
  "push.device_registered": {
    subject: "push-devices",
    payload: ["deviceId", "userId", "platform", "provider"],
  },
  "push.device_unregistered": {
    subject: "push-devices",
    payload: ["deviceId", "userId"],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  options: ["extraColumns"],
  tables: {
    devices: {
      name: "push_devices",
      app: {},
      lifecycle: { user: "user" },
      columns: {
        id: "id",
        user: "user_id",
        token: "token",
        platform: "platform",
        provider: "provider",
        deviceName: "device_name",
        appVersion: "app_version",
        createdAt: "created_at",
        lastSeenAt: "last_seen_at",
      },
      optional: ["deviceName", "appVersion", "createdAt", "lastSeenAt"],
      typed: ["platform", "provider"],
    },
    tickets: {
      name: "push_tickets",
      app: {},
      columns: {
        id: "id",
        delivery: "delivery_id",
        token: "token",
        ticket: "ticket_id",
        status: "status",
        error: "error",
        createdAt: "created_at",
        checkedAt: "checked_at",
      },
      optional: ["error"],
      typed: ["status"],
      optionalTable: true,
    },
  },
};

/** `options.extraColumns`, added to the devices table. */
const extrasOf = (ctx: BlockSqlContext) => ctx.extraColumns("devices");

const PLATFORMS = ["ios", "android", "web"];
const PROVIDERS = ["expo", "fcm", "apns", "webpush"];

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const d = ctx.table("devices");
  const c = (logical: string): string => ctx.col("devices", logical);
  const fn = (name: string): string => ctx.fn(name);
  const has = (logical: string): boolean => ctx.has("devices", logical);
  const extras = extrasOf(ctx);
  const name = ctx.tableName("devices").name;

  const list = (values: readonly string[]): string =>
    values.map((value) => `'${value}'`).join(", ");

  const optional = (
    logical: string,
    definition: (column: string) => string,
  ): string =>
    has(logical) ? `,\n  ${c(logical)} ${definition(c(logical))}` : "";

  const written = (
    [
      ["user", "v_user"],
      ["token", "register_push_device.token"],
      [
        "platform",
        ctx.cast("devices", "platform", "register_push_device.platform"),
      ],
      [
        "provider",
        ctx.cast("devices", "provider", "register_push_device.provider"),
      ],
      ["deviceName", "left(register_push_device.device_name, 200)"],
      ["appVersion", "left(register_push_device.app_version, 50)"],
    ] as const
  ).filter(([logical]) => has(logical));

  const refreshed = [
    `${c("user")} = excluded.${c("user")}`,
    `${c("platform")} = excluded.${c("platform")}`,
    `${c("provider")} = excluded.${c("provider")}`,
    ...["deviceName", "appVersion"]
      .filter(has)
      .map(
        (logical) =>
          `${c(logical)} = coalesce(excluded.${c(logical)}, x.${c(logical)})`,
      ),
    ...(has("lastSeenAt") ? [`${c("lastSeenAt")} = now()`] : []),
  ];

  const recent = has("lastSeenAt") ? `, x.${c("lastSeenAt")} desc` : "";

  const registered = ctx.record({
    type: "push.device_registered",
    payload: `jsonb_build_object('deviceId', v_id::text, 'userId', v_user::text, 'platform', register_push_device.platform, 'provider', register_push_device.provider)`,
    subject: `'push-devices/' || v_id::text`,
    audit: {
      category: "security",
      targetType: "push_device",
      recordId: "v_id::text",
    },
  });

  const unregistered = ctx.record({
    type: "push.device_unregistered",
    payload: `jsonb_build_object('deviceId', v_id::text, 'userId', v_user::text)`,
    subject: `'push-devices/' || v_id::text`,
    audit: {
      category: "security",
      targetType: "push_device",
      recordId: "v_id::text",
    },
  });

  const serviceOnly = (name: string): string => `
  if not (${SERVICE_CALLER}) then
    ${fail("PUSH_FORBIDDEN", "only the service role reads push tokens")}
  end if;
  if ${name} is null or cardinality(${name}) > 1000 then
    ${fail("PUSH_TOO_MANY", "pass at most 1000 values", "22023")}
  end if;`;

  return `${schemaPreamble(ctx)}
-- The push tokens of each user's devices. A token belongs to one user: a
-- device that signs in as someone else moves its token to them. Apps write
-- through register_push_device and unregister_push_device; the sender reads
-- tokens with push_tokens_for and drops the ones the provider rejects with
-- prune_push_tokens, both service role only.
create table if not exists ${d} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("user")} uuid not null references auth.users (id) on delete cascade,
  ${c("token")} text not null unique check (length(${c("token")}) between 1 and 4096),
  ${c("platform")} text not null check (${c("platform")} in (${list(PLATFORMS)})),
  ${c("provider")} text not null default 'expo' check (${c("provider")} in (${list(PROVIDERS)}))${optional("deviceName", (column) => `text check (length(${column}) <= 200)`)}${optional("appVersion", (column) => `text check (length(${column}) <= 50)`)}${optional("createdAt", () => "timestamptz not null default now()")}${optional("lastSeenAt", () => "timestamptz not null default now()")}
);
create index if not exists push_devices_user_idx on ${d} (${c("user")});${ctx.owns("devices") ? "" : `\ncreate unique index if not exists ${sqlIdent(`bsb_${name}_token_key`)} on ${d} (${c("token")});`}${addExtraColumns(d, extras)}
alter table ${d} enable row level security;
${revokeTable(d)}
grant select, delete on ${d} to authenticated;
grant all on ${d} to service_role;
${renderPolicy(makePolicy({ table: d, name: "push_devices_own_read", command: "select", roles: ["authenticated"], using: `${c("user")} = (select auth.uid())` }), { drop: true, target: d })}
${renderPolicy(makePolicy({ table: d, name: "push_devices_own_delete", command: "delete", roles: ["authenticated"], using: `${c("user")} = (select auth.uid())` }), { drop: true, target: d })}

-- Registers the caller's device, or refreshes it; returns the device id.
${extraFieldsArg(extras).drop(fn("register_push_device"), "text, text, text, text, text")}
create or replace function ${fn("register_push_device")}(
  token text,
  platform text,
  provider text default 'expo',
  device_name text default null,
  app_version text default null${extraFieldsArg(extras).param}
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_new boolean;
begin
  if v_user is null then
    ${fail("PUSH_FORBIDDEN", "Sign in first")}
  end if;
  if register_push_device.platform is null or register_push_device.platform not in (${list(PLATFORMS)}) then
    ${raise("Unknown push platform %", "22023", "PUSH_PLATFORM", "register_push_device.platform")}
  end if;
  if register_push_device.provider is null or register_push_device.provider not in (${list(PROVIDERS)}) then
    ${raise("Unknown push provider %", "22023", "PUSH_PROVIDER", "register_push_device.provider")}
  end if;
  if register_push_device.token is null or length(register_push_device.token) not between 1 and 4096 then
    ${fail("PUSH_TOKEN", "A push token is 1 to 4096 characters", "22023")}
  end if;
  insert into ${d} as x (${written.map(([logical]) => c(logical)).join(", ")})
  values (
    ${written.map(([, value]) => value).join(",\n    ")}
  )
  on conflict (${c("token")}) do update set
    ${refreshed.join(",\n    ")}
  returning x.${c("id")}, (x.xmax = 0) into v_id, v_new;${writeExtraColumns(d, extras, "register_push_device.fields", `x.${c("id")} = v_id`)}
  if v_new then
    ${registered}
  end if;
  return v_id;
end;
$$;

-- Removes the caller's device with token, e.g. on sign-out; false when the
-- caller had none.
create or replace function ${fn("unregister_push_device")}(token text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_id uuid;
begin
  if v_user is null and not (${SERVICE_CALLER}) then
    ${fail("PUSH_FORBIDDEN", "Sign in first")}
  end if;
  delete from ${d} x
  where x.${c("token")} = unregister_push_device.token
    and (${SERVICE_CALLER} or x.${c("user")} = v_user)
  returning x.${c("id")}, x.${c("user")} into v_id, v_user;
  if v_id is null then
    return false;
  end if;
  ${unregistered}
  return true;
end;
$$;

-- [{ userId, token, platform, provider }] for every device of users.
create or replace function ${fn("push_tokens_for")}(users uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${serviceOnly("push_tokens_for.users")}
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', x.${c("user")},
      'token', x.${c("token")},
      'platform', x.${c("platform")},
      'provider', x.${c("provider")}${extraFieldsJson("x", extras)}
    ) order by x.${c("user")}${recent}), '[]'::jsonb)
    from ${d} x
    where x.${c("user")} = any (push_tokens_for.users)
  );
end;
$$;

-- Deletes the devices with tokens the provider rejected; returns how many.
create or replace function ${fn("prune_push_tokens")}(tokens text[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin${serviceOnly("prune_push_tokens.tokens")}
  delete from ${d} x where x.${c("token")} = any (prune_push_tokens.tokens);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function ${fn("register_push_device")}(text, text, text, text, text${extraFieldsArg(extras).type}) from public, anon;
revoke execute on function ${fn("unregister_push_device")}(text) from public, anon;
revoke execute on function ${fn("push_tokens_for")}(uuid[]) from public, anon, authenticated;
revoke execute on function ${fn("prune_push_tokens")}(text[]) from public, anon, authenticated;
grant execute on function ${fn("register_push_device")}(text, text, text, text, text${extraFieldsArg(extras).type}) to authenticated, service_role;
grant execute on function ${fn("unregister_push_device")}(text) to authenticated, service_role;
grant execute on function ${fn("push_tokens_for")}(uuid[]) to service_role;
grant execute on function ${fn("prune_push_tokens")}(text[]) to service_role;
${pushTickets(ctx)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "register_push_device",
      args: [
        "text",
        "text",
        "text",
        "text",
        "text",
        ...extraFieldsArg(extrasOf(ctx)).contract,
      ],
      returns: "uuid",
    },
    { name: "unregister_push_device", args: ["text"], returns: "boolean" },
    { name: "push_tokens_for", args: ["uuid[]"], returns: "jsonb" },
    { name: "prune_push_tokens", args: ["text[]"], returns: "integer" },
    ...ticketsContract(ctx),
  ];
}

export const PUSH: BlockSqlDefinition = {
  name: "push",
  title: "Push devices",
  description:
    "The push tokens of each user's devices (Expo, FCM, APNs or Web Push) with RLS, behind register_push_device and unregister_push_device for the user and push_tokens_for and prune_push_tokens for the service role. With notifications, push_tickets keeps Expo's tickets per delivery for the receipt check. better-supabase/blocks/push registers Expo devices and sends through the Expo Push API.",
  requires: [],
  integrates: ["notifications"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  upgrades: [
    {
      from: 1,
      description:
        "With the notifications block installed, push_tickets stores Expo's tickets per delivery; record_push_tickets, push_tickets_for, unchecked_push_tickets and complete_push_receipts are new, for retries that skip devices already sent to and the receipt check.",
      sql: () => "",
    },
    {
      from: 2,
      description:
        "complete_push_receipts returns { updated, events }: the ticket count and the provider events it recorded for the first time, so the client emits notification.delivered and notification.bounced like recordDeliveryEvent does.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract,
  build,
};
