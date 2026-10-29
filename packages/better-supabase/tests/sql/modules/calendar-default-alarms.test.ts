import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ADMIN = "22222222-2222-4222-8222-222222222222";
const ALICE = "33333333-3333-4333-8333-333333333333";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const KEYS = `
create table public.test_keys (user_id uuid, tenant uuid, key text);
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select exists (select 1 from public.test_keys k where k.user_id = auth.uid() and k.tenant = scope_id and k.key = permission)
$$;
insert into public.test_keys (user_id, tenant, key) values
  ('${ADMIN}', '${TENANT}', 'calendar.read'), ('${ADMIN}', '${TENANT}', 'calendar.write'), ('${ADMIN}', '${TENANT}', 'calendar.manage'),
  ('${ALICE}', '${TENANT}', 'calendar.read'), ('${ALICE}', '${TENANT}', 'calendar.write');
`;

const as = (role: string, user = ""): string =>
  `perform set_config('request.jwt.claims', '{"role":"${role}","sub":"${user}"}', true);
  perform set_config('request.jwt.claim.role', '${role}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);`;

const forbidden = (statement: string, hint: string, label: string): string => `
  begin
    ${statement};
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> '${hint}' then
    raise exception '${label}: %', v_hint;
  end if;`;

const CHECK = `do $$
declare
  v_calendar uuid;
  v_event uuid;
  v_defaults jsonb;
  v_hint text;
begin
  ${as("authenticated", ADMIN)}
  v_calendar := (better_supabase.create_calendar('${TENANT}', 'Team', 'UTC', null, null) ->> 'id')::uuid;
  v_defaults := better_supabase.set_calendar_default_alarms(v_calendar, '[{"offsetMinutes": 10}, {"offsetMinutes": 60, "method": "email"}, {"allDay": true, "offsetMinutes": 1440, "anchor": "08:30"}]');
  if jsonb_array_length(v_defaults) <> 3 or v_defaults -> 2 ->> 'anchor' <> '08:30' then
    raise exception 'defaults %', v_defaults;
  end if;
  ${forbidden(`perform better_supabase.set_calendar_default_alarms(v_calendar, '[{"offsetMinutes": 1.5}]')`, "CALENDAR_ALARM_INVALID", "fractional offset")}
  ${forbidden(`perform better_supabase.set_calendar_default_alarms(v_calendar, '[{"offsetMinutes": 5, "anchor": "09:00"}]')`, "CALENDAR_ALARM_INVALID", "anchor on a timed alarm")}

  ${as("authenticated", ALICE)}
  ${forbidden(`perform better_supabase.set_calendar_default_alarms(v_calendar, '[]')`, "CALENDAR_FORBIDDEN", "member sets defaults")}
  v_event := (better_supabase.save_calendar_event(v_calendar, '{"title": "Standup", "startsAt": "2026-03-02T09:00:00Z", "endsAt": "2026-03-02T09:15:00Z"}') ->> 'id')::uuid;
  if (select array_agg(offset_minutes order by offset_minutes) from better_supabase.calendar_event_alarms where event_id = v_event) <> array[10, 60] then
    raise exception 'timed defaults %', (select jsonb_agg(to_jsonb(a)) from better_supabase.calendar_event_alarms a);
  end if;
  if (select created_by from better_supabase.calendar_events where id = v_event) <> '${ALICE}' then
    raise exception 'creator';
  end if;
  v_event := (better_supabase.save_calendar_event(v_calendar, '{"title": "Offsite", "allDay": true, "startsAt": "2026-03-05T00:00:00Z", "endsAt": "2026-03-06T00:00:00Z"}') ->> 'id')::uuid;
  if (select array_agg(offset_minutes) from better_supabase.calendar_event_alarms where event_id = v_event) <> array[930] then
    raise exception 'all-day defaults %', (select jsonb_agg(to_jsonb(a)) from better_supabase.calendar_event_alarms a where event_id = v_event);
  end if;
  v_event := (better_supabase.save_calendar_event(v_calendar, '{"title": "Quiet", "startsAt": "2026-03-02T10:00:00Z", "endsAt": "2026-03-02T11:00:00Z", "alarms": []}') ->> 'id')::uuid;
  if exists (select 1 from better_supabase.calendar_event_alarms where event_id = v_event) then
    raise exception 'explicit empty alarms got defaults';
  end if;
  ${forbidden(`perform better_supabase.save_calendar_event(v_calendar, '{"title": "As admin", "startsAt": "2026-03-02T10:00:00Z", "endsAt": "2026-03-02T11:00:00Z"}', '${ADMIN}')`, "CALENDAR_FORBIDDEN", "member names another actor")}

  ${as("service_role")}
  v_event := (better_supabase.save_calendar_event(v_calendar, '{"title": "Synced", "startsAt": "2026-03-03T09:00:00Z", "endsAt": "2026-03-03T10:00:00Z"}', '${ALICE}') ->> 'id')::uuid;
  if (select created_by from better_supabase.calendar_events where id = v_event) is distinct from '${ALICE}' then
    raise exception 'service role actor';
  end if;
end;
$$;`;

describe("calendar default alarms", () => {
  it("renders nothing without the option", () => {
    const sql = renderBlocks(["calendar"], {})
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("calendar_default_alarms");
    expect(sql).toContain("actor uuid default null");
  });

  it("refuses the option without the alarms table", () => {
    expect(() =>
      renderBlocks(["calendar"], {
        modules: {
          calendar: {
            tables: { alarms: null },
            options: { defaultAlarms: true },
          },
        },
      }),
    ).toThrow(/defaultAlarms needs the alarms/u);
  });

  it(
    "copies a calendar's defaults onto new events and saves as an actor for the service role",
    { timeout: 60_000 },
    async () => {
      const files = renderBlocks(["calendar"], {
        modules: { calendar: { options: { defaultAlarms: true } } },
      });

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          ROLES,
          ...files
            .filter((file) => file.kind !== "data")
            .map((file) => file.contents),
        ],
        seed: [
          ...files
            .filter((file) => file.kind === "data")
            .map((file) => file.contents),
          KEYS,
          CHECK,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );
});
