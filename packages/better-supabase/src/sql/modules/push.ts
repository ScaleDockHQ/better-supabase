import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { schemaPreamble, SERVICE_CALLER } from "../shared.ts";

const NAMES: ModuleNames = {
  tables: {
    devices: {
      name: "push_devices",
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
    },
  },
};

const PLATFORMS = ["ios", "android", "web"];
const PROVIDERS = ["expo", "fcm", "apns", "webpush"];

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const d = ctx.table("devices");
  const c = (logical: string): string => ctx.col("devices", logical);
  const fn = (name: string): string => ctx.fn(name);
  const list = (values: readonly string[]): string =>
    values.map((value) => `'${value}'`).join(", ");
  const registered = ctx.record({
    type: "push.device_registered",
    payload: `jsonb_build_object('deviceId', v_id::text, 'userId', v_user::text, 'platform', register_push_device.platform, 'provider', register_push_device.provider)`,
    subject: `'push_devices/' || v_id::text`,
    audit: {
      category: "security",
      targetType: "push_device",
      recordId: "v_id::text",
    },
  });
  const unregistered = ctx.record({
    type: "push.device_unregistered",
    payload: `jsonb_build_object('deviceId', v_id::text, 'userId', v_user::text)`,
    subject: `'push_devices/' || v_id::text`,
    audit: {
      category: "security",
      targetType: "push_device",
      recordId: "v_id::text",
    },
  });
  const serviceOnly = (name: string): string => `
  if not (${SERVICE_CALLER}) then
    raise exception 'only the service role reads push tokens' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if ${name} is null or cardinality(${name}) > 1000 then
    raise exception 'pass at most 1000 values' using errcode = '22023', hint = 'PUSH_TOO_MANY';
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
  ${c("provider")} text not null default 'expo' check (${c("provider")} in (${list(PROVIDERS)})),
  ${c("deviceName")} text check (length(${c("deviceName")}) <= 200),
  ${c("appVersion")} text check (length(${c("appVersion")}) <= 50),
  ${c("createdAt")} timestamptz not null default now(),
  ${c("lastSeenAt")} timestamptz not null default now()
);
create index if not exists push_devices_user_idx on ${d} (${c("user")});
alter table ${d} enable row level security;
revoke all on ${d} from anon, authenticated;
grant select, delete on ${d} to authenticated;
grant all on ${d} to service_role;
drop policy if exists "push_devices_own_read" on ${d};
create policy "push_devices_own_read" on ${d} for select to authenticated
  using (${c("user")} = (select auth.uid()));
drop policy if exists "push_devices_own_delete" on ${d};
create policy "push_devices_own_delete" on ${d} for delete to authenticated
  using (${c("user")} = (select auth.uid()));

-- Registers the caller's device, or refreshes it; returns the device id.
create or replace function ${fn("register_push_device")}(
  token text,
  platform text,
  provider text default 'expo',
  device_name text default null,
  app_version text default null
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
    raise exception 'Sign in first' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if register_push_device.platform is null or register_push_device.platform not in (${list(PLATFORMS)}) then
    raise exception 'Unknown push platform %', register_push_device.platform using errcode = '22023', hint = 'PUSH_PLATFORM';
  end if;
  if register_push_device.provider is null or register_push_device.provider not in (${list(PROVIDERS)}) then
    raise exception 'Unknown push provider %', register_push_device.provider using errcode = '22023', hint = 'PUSH_PROVIDER';
  end if;
  if register_push_device.token is null or length(register_push_device.token) not between 1 and 4096 then
    raise exception 'A push token is 1 to 4096 characters' using errcode = '22023', hint = 'PUSH_TOKEN';
  end if;
  insert into ${d} as x (${c("user")}, ${c("token")}, ${c("platform")}, ${c("provider")}, ${c("deviceName")}, ${c("appVersion")})
  values (
    v_user,
    register_push_device.token,
    register_push_device.platform,
    register_push_device.provider,
    left(register_push_device.device_name, 200),
    left(register_push_device.app_version, 50)
  )
  on conflict (${c("token")}) do update set
    ${c("user")} = excluded.${c("user")},
    ${c("platform")} = excluded.${c("platform")},
    ${c("provider")} = excluded.${c("provider")},
    ${c("deviceName")} = coalesce(excluded.${c("deviceName")}, x.${c("deviceName")}),
    ${c("appVersion")} = coalesce(excluded.${c("appVersion")}, x.${c("appVersion")}),
    ${c("lastSeenAt")} = now()
  returning x.${c("id")}, (x.xmax = 0) into v_id, v_new;
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
    raise exception 'Sign in first' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
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
      'provider', x.${c("provider")}
    ) order by x.${c("user")}, x.${c("lastSeenAt")} desc), '[]'::jsonb)
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

revoke execute on function ${fn("register_push_device")}(text, text, text, text, text) from public, anon;
revoke execute on function ${fn("unregister_push_device")}(text) from public, anon;
revoke execute on function ${fn("push_tokens_for")}(uuid[]) from public, anon, authenticated;
revoke execute on function ${fn("prune_push_tokens")}(text[]) from public, anon, authenticated;
grant execute on function ${fn("register_push_device")}(text, text, text, text, text) to authenticated, service_role;
grant execute on function ${fn("unregister_push_device")}(text) to authenticated, service_role;
grant execute on function ${fn("push_tokens_for")}(uuid[]) to service_role;
grant execute on function ${fn("prune_push_tokens")}(text[]) to service_role;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "register_push_device",
      args: ["text", "text", "text", "text", "text"],
      returns: "uuid",
    },
    { name: "unregister_push_device", args: ["text"], returns: "boolean" },
    { name: "push_tokens_for", args: ["uuid[]"], returns: "jsonb" },
    { name: "prune_push_tokens", args: ["text[]"], returns: "integer" },
  ];
}

export const PUSH: ModuleDefinition = {
  name: "push",
  title: "Push devices",
  description:
    "The push tokens of each user's devices (Expo, FCM, APNs or Web Push) with RLS, behind register_push_device and unregister_push_device for the user and push_tokens_for and prune_push_tokens for the service role. better-supabase/blocks/push registers Expo devices and sends through the Expo Push API.",
  requires: [],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
