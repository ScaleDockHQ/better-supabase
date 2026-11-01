import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type {
  BlockSqlAccessProvider,
  BlockSqlLayout,
} from "../../src/sql/module-types.ts";

import { createCalendar } from "../../src/blocks/calendar/calendar.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const rows = (schema: string, resource: string): string => `
create function ${schema}.rows_${resource}(permission text, ids text[]) returns setof text
  language sql stable security definer set search_path = '' as $$
    select g.row_id from (
      select r.user_id, r.row_id, r.permission from ${schema}.row_grants r
      union all
      select m.user_id, r.row_id, r.permission from ${schema}.role_grants r
      join better_supabase.memberships m on m.role = r.role
      union all
      select t.user_id, r.row_id, r.permission from ${schema}.team_grants r
      join ${schema}.team_members t on t.team_id = r.team_id
    ) g
    where g.user_id = auth.uid()
      and g.permission = rows_${resource}.permission
      and (ids is null or g.row_id = any (ids))
      and not exists (select 1 from ${schema}.disabled d where d.user_id = g.user_id)
  $$;
create function ${schema}.rows_${resource}_for(p_user uuid, p_permission text) returns setof text
  language plpgsql volatile security definer set search_path = '' as $$
  declare
    v_claims text := pg_catalog.current_setting('request.jwt.claims', true);
  begin
    perform pg_catalog.set_config('request.jwt.claims',
      pg_catalog.jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
    return query select r from ${schema}.rows_${resource}(p_permission, null) r;
    perform pg_catalog.set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end
  $$;
revoke execute on function ${schema}.rows_${resource}_for(uuid, text) from public, anon, authenticated;`;

const provider = (schema: string): string => `
set local check_function_bodies = off;
create schema ${schema};
grant usage on schema ${schema} to anon, authenticated;
create table ${schema}.row_grants (user_id uuid, row_id text, permission text);
create table ${schema}.disabled (user_id uuid primary key);
create table ${schema}.role_grants (role text, row_id text, permission text);
create table ${schema}.team_members (team_id uuid, user_id uuid);
create table ${schema}.team_grants (team_id uuid, row_id text, permission text);
create function ${schema}.ids_with_for(p_user uuid, permission text) returns setof uuid
  language sql stable security definer set search_path = '' as $$
    select m.organization_id from better_supabase.memberships m
    where m.user_id = p_user
      and not exists (select 1 from ${schema}.disabled d where d.user_id = p_user)
  $$;
create function ${schema}.ids_with(permission text) returns setof uuid
  language sql stable security definer set search_path = '' as $$
    select ${schema}.ids_with_for(auth.uid(), permission)
  $$;
create function ${schema}.is_platform(permission text) returns boolean
  language sql stable as $$ select false $$;
create function ${schema}.is_platform_for(p_user uuid, permission text) returns boolean
  language sql stable as $$ select false $$;
${rows(schema, "agenda_calendar")}
${rows(schema, "file_node")}
create function ${schema}.readable(calendar_id uuid, user_id uuid) returns boolean
  language sql stable security definer set search_path = '' as $$
    select user_id = (select auth.uid())
      and calendar_id::text in (
        select ${schema}.rows_agenda_calendar('agendaCalendar.read', array[calendar_id::text])
      )
  $$;
grant execute on function ${schema}.readable(uuid, uuid) to authenticated;
create function ${schema}.node_role(node_id uuid, user_id uuid) returns text
  language sql stable security definer set search_path = '' as $$
    select case
      when user_id = (select auth.uid()) and node_id::text in (
        select ${schema}.rows_file_node('fileNode.update', array[node_id::text])
      ) then 'editor'
      when user_id = (select auth.uid()) and node_id::text in (
        select ${schema}.rows_file_node('fileNode.read', array[node_id::text])
      ) then 'viewer'
    end
  $$;
grant execute on function ${schema}.node_role(uuid, uuid) to authenticated;
set local check_function_bodies = on;
`;

const accessProvider = (schema: string): BlockSqlAccessProvider => ({
  name: "test",
  scope: "organization",
  idType: "uuid",
  functions: {
    idsWith: `${schema}.ids_with({permission})`,
    idsWithFor: `${schema}.ids_with_for({user}, {permission})`,
    isPlatform: `${schema}.is_platform({permission})`,
    isPlatformFor: `${schema}.is_platform_for({user}, {permission})`,
    rowsWith: `${schema}.rows_{resource}({permission}, {ids})`,
    rowsWithFor: `${schema}.rows_{resource}_for({user}, {permission})`,
  },
});

const layout = (schema: string): BlockSqlLayout => ({
  modules: {
    permissions: { model: "provider" },
    calendar: {
      schema: "calendar_rows",
      options: {
        access: true,
        accessFunctions: {
          read: { rows: "agenda_calendar", key: "agendaCalendar.read" },
          write: { rows: "agenda_calendar", key: "agendaCalendar.update" },
        },
      },
    },
  },
  accessProvider: accessProvider(schema),
});

describe.skipIf(!live)("block access over the provider's row grants", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("answers calendar access like a hand-written adapter, for the caller only", async () => {
    const s = await BlockSession.open(pool);

    try {
      const schema = `rows_${crypto.randomUUID().slice(0, 8)}`;
      await s.client.query(provider(schema));
      await s.install(["organizations", "share-links", "calendar"], {
        ...layout(schema),
      });

      const owner = await s.user("owner");
      const alice = await s.user("alice");
      const bob = await s.user("bob");
      const org = await s.organization(owner, { admin: alice, admin2: bob });

      const calendar = createCalendar({
        transport: sqlTransport(s.sql),
        schema: "calendar_rows",
      });

      await s.service();

      const { id: granted } = await calendar
        .createCalendar({ organizationId: org, name: "Granted" })
        .orThrow();

      const { id: other } = await calendar
        .createCalendar({ organizationId: org, name: "Other" })
        .orThrow();

      await s.client.query(
        `insert into ${schema}.row_grants values ($1, $2, 'agendaCalendar.read')`,
        [alice.id, granted],
      );

      await s.asRole(alice);

      for (const id of [granted, other]) {
        expect(
          await s.value<boolean>(
            "calendar_rows.calendar_access($1, $2, 'read')",
            [id, alice.id],
          ),
        ).toBe(
          await s.value<boolean>(`${schema}.readable($1, $2)`, [id, alice.id]),
        );
      }

      expect(
        await s.value<boolean>(
          "calendar_rows.calendar_access($1, $2, 'read')",
          [granted, alice.id],
        ),
      ).toBe(true);

      await s.asRole(bob);
      expect(
        await s.value<boolean>(
          "calendar_rows.calendar_access($1, $2, 'read')",
          [granted, alice.id],
        ),
      ).toBe(false);
      expect(
        await s.hint("calendar_rows.calendar_access_for($1, $2, 'read')", [
          granted,
          alice.id,
        ]),
      ).toMatch(/permission denied/u);
    } finally {
      await s.close();
    }
  });

  it("serves a calendar feed for its creator with nobody signed in, until the grant goes", async () => {
    const s = await BlockSession.open(pool);

    try {
      const schema = `rows_${crypto.randomUUID().slice(0, 8)}`;
      await s.client.query(provider(schema));
      await s.install(["organizations", "share-links", "calendar"], {
        ...layout(schema),
      });

      const owner = await s.user("owner");
      const alice = await s.user("alice");
      const org = await s.organization(owner, { admin: alice });

      const calendar = createCalendar({
        transport: sqlTransport(s.sql),
        schema: "calendar_rows",
      });

      await s.service();

      const { id } = await calendar
        .createCalendar({ organizationId: org, name: "Team" })
        .orThrow();

      await s.client.query(
        `insert into ${schema}.row_grants values ($1, $2, 'agendaCalendar.read'), ($1, $2, 'agendaCalendar.update')`,
        [alice.id, id],
      );

      await s.as(alice);
      await calendar
        .upsert({
          calendarId: id,
          input: {
            title: "Standup",
            startsAt: Temporal.Now.instant().add({ hours: 24 }),
            endsAt: Temporal.Now.instant().add({ hours: 25 }),
          },
        })
        .orThrow();

      const link = await s.value<{ token: string }>(
        "better_supabase.create_share_link($1, 'calendar', $2, 'view')",
        [org, id],
      );

      await s.asRole("anon");
      expect(await calendar.feed(link.token).orThrow()).toContain(
        "SUMMARY:Standup",
      );

      await s.service();
      await s.client.query(`insert into ${schema}.disabled values ($1)`, [
        alice.id,
      ]);
      await s.asRole("anon");
      expect(await calendar.feed(link.token).orThrow()).toBeNull();

      await s.service();
      await s.client.query(`delete from ${schema}.disabled`);
      await s.client.query(
        `delete from ${schema}.row_grants where permission = 'agendaCalendar.read'`,
      );
      await s.asRole("anon");
      expect(await calendar.feed(link.token).orThrow()).toBeNull();
    } finally {
      await s.close();
    }
  });

  it("serves a calendar feed for a creator whose access comes from a role or a team", async () => {
    const s = await BlockSession.open(pool);

    try {
      const schema = `rows_${crypto.randomUUID().slice(0, 8)}`;
      await s.client.query(provider(schema));
      await s.install(["organizations", "share-links", "calendar"], {
        ...layout(schema),
      });

      const owner = await s.user("owner");
      const byRole = await s.user("by-role");
      const byTeam = await s.user("by-team");

      const org = await s.organization(owner, {
        viewer: byRole,
        member: byTeam,
      });

      const calendar = createCalendar({
        transport: sqlTransport(s.sql),
        schema: "calendar_rows",
      });

      await s.service();

      const { id } = await calendar
        .createCalendar({ organizationId: org, name: "Team" })
        .orThrow();

      const team = crypto.randomUUID();
      await s.client.query(
        `insert into ${schema}.role_grants values ('viewer', $1, 'agendaCalendar.read'), ('viewer', $1, 'agendaCalendar.update')`,
        [id],
      );
      await s.client.query(
        `insert into ${schema}.team_members values ($1, $2)`,
        [team, byTeam.id],
      );
      await s.client.query(
        `insert into ${schema}.team_grants values ($1, $2, 'agendaCalendar.read'), ($1, $2, 'agendaCalendar.update')`,
        [team, id],
      );
      await calendar
        .upsert({
          calendarId: id,
          input: {
            title: "Retro",
            startsAt: Temporal.Now.instant().add({ hours: 24 }),
            endsAt: Temporal.Now.instant().add({ hours: 25 }),
          },
        })
        .orThrow();

      const tokens: string[] = [];

      for (const creator of [byRole, byTeam]) {
        await s.as(creator);

        const link = await s.value<{ token: string }>(
          "better_supabase.create_share_link($1, 'calendar', $2, 'view')",
          [org, id],
        );

        tokens.push(link.token);
        await s.asRole("anon");
        expect(await calendar.feed(link.token).orThrow()).toContain(
          "SUMMARY:Retro",
        );
        await s.service();
      }

      await s.client.query(`delete from ${schema}.role_grants`);
      await s.client.query(`delete from ${schema}.team_members`);
      await s.asRole("anon");

      for (const token of tokens) {
        expect(await calendar.feed(token).orThrow()).toBeNull();
      }
    } finally {
      await s.close();
    }
  });

  it("maps the provider's row grants to drive node roles like a hand-written function", async () => {
    const s = await BlockSession.open(pool);

    try {
      const schema = `rows_${crypto.randomUUID().slice(0, 8)}`;
      await s.client.query(provider(schema));
      await s.install(["organizations", "outbox", "teams", "drive"], {
        modules: {
          permissions: { model: "provider" },
          drive: {
            options: {
              roleFunctions: {
                node: {
                  rows: "file_node",
                  roles: { viewer: "fileNode.read", editor: "fileNode.update" },
                },
              },
            },
          },
        },
        accessProvider: accessProvider(schema),
      });

      const owner = await s.user("owner");
      const alice = await s.user("alice");
      const tenant = await s.organization(owner, { member: alice });

      await s.service();

      const { id } = await s.value<{ id: string }>(
        "better_supabase.drive_create_folder($1, null, 'Projects')",
        [tenant],
      );

      const roles = async () => {
        await s.asRole(alice);

        const role = await s.value<string | null>(
          "better_supabase.drive_role($1)",
          [id],
        );

        const expected = await s.value<string | null>(
          `${schema}.node_role($1, $2)`,
          [id, alice.id],
        );

        const readable = await s.value<boolean>(
          "$1::uuid in (select better_supabase.drive_readable_ids())",
          [id],
        );

        await s.service();

        return { role, expected, readable };
      };

      expect(await roles()).toEqual({
        role: null,
        expected: null,
        readable: false,
      });

      await s.client.query(
        `insert into ${schema}.row_grants values ($1, $2, 'fileNode.read')`,
        [alice.id, id],
      );
      expect(await roles()).toEqual({
        role: "viewer",
        expected: "viewer",
        readable: true,
      });

      await s.client.query(
        `insert into ${schema}.row_grants values ($1, $2, 'fileNode.update')`,
        [alice.id, id],
      );
      expect(await roles()).toEqual({
        role: "editor",
        expected: "editor",
        readable: true,
      });
    } finally {
      await s.close();
    }
  });
});
