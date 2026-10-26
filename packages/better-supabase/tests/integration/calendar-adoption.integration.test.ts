import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createCalendar } from "../../src/blocks/calendar/calendar.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const range = {
  from: at("2026-03-01T00:00:00Z"),
  until: at("2026-04-01T00:00:00Z"),
};

const APP = `
create schema cal_app;
grant usage on schema cal_app to authenticated, service_role;
create type cal_app.visibility as enum ('team', 'personal');
create type cal_app.freq as enum ('daily', 'weekly', 'monthly', 'yearly');
create type cal_app.date_kind as enum ('extra', 'skip');
create table cal_app.calendars (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null,
  timezone text not null default 'UTC',
  owner_user_id uuid,
  visibility cal_app.visibility not null default 'team',
  created_at timestamptz not null default now()
);
create table cal_app.events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  calendar_id uuid not null references cal_app.calendars (id) on delete cascade,
  uid text not null,
  title text not null default '',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  all_day boolean not null default false,
  timezone text not null default 'UTC',
  status text not null default 'confirmed',
  recurrence_id uuid references cal_app.events (id) on delete cascade,
  original_start timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table cal_app.event_rules (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references cal_app.events (id) on delete cascade,
  frequency cal_app.freq not null,
  every integer,
  occurrences integer,
  ends_at timestamptz,
  weekdays text[]
);
create table cal_app.event_dates (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references cal_app.events (id) on delete cascade,
  kind cal_app.date_kind not null,
  occurs_at timestamptz not null
);
`;

describe.skipIf(!live)("calendar adoption options", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("keeps private calendars and events to their owners on the block's tables", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const alice = await s.user("alice");
      const bob = await s.user("bob");

      await s.install(["organizations", "share-links", "calendar"], {
        modules: {
          calendar: {
            schema: "calendar_adopt",
            options: {
              access: true,
              userFeed: true,
              rdates: true,
              attendeeKey: "any",
              calendarDetails: true,
            },
          },
        },
      });

      const org = await s.organization(owner, { member: alice, member2: bob });

      const calendar = createCalendar({
        transport: sqlTransport(s.sql),
        schema: "calendar_adopt",
      });

      await s.as(alice);

      const { id: mine } = await calendar
        .createCalendar(org, "Alice", {
          ownerType: "user",
          ownerId: alice.id,
          visibility: "private",
          description: "Personal",
        })
        .orThrow();

      const series = await calendar
        .upsert(mine, {
          title: "Physio",
          visibility: "private",
          startsAt: at("2026-03-02T09:00:00Z"),
          endsAt: at("2026-03-02T10:00:00Z"),
          rrule: "FREQ=WEEKLY;COUNT=2",
          rdates: [at("2026-03-05T09:00:00Z")],
        })
        .orThrow();

      expect(
        (await calendar.occurrences([mine], range).orThrow()).map((item) =>
          item.start.toString(),
        ),
      ).toEqual([
        "2026-03-02T09:00:00Z",
        "2026-03-05T09:00:00Z",
        "2026-03-09T09:00:00Z",
      ]);
      expect(
        await calendar
          .setAttendee(series.id, { subjectType: "contact", subjectId: "c-1" })
          .orThrow(),
      ).toBe(true);

      await s.asRole(bob);
      expect(await calendar.occurrences([mine], range).orThrow()).toEqual([]);
      expect(
        hint(
          await calendar.upsert(mine, {
            title: "Peek",
            startsAt: at("2026-03-03T09:00:00Z"),
            endsAt: at("2026-03-03T10:00:00Z"),
          }),
        ),
      ).toBe("CALENDAR_FORBIDDEN");
      expect(hint(await calendar.delete(series.id))).toBe("CALENDAR_FORBIDDEN");

      const busy = await calendar
        .freeBusy(org, [alice.id], {
          from: at("2026-03-01T00:00:00Z"),
          until: at("2026-03-08T00:00:00Z"),
        })
        .orThrow();

      expect(busy[0]?.busy).toHaveLength(2);

      await s.as(owner);
      expect(hint(await calendar.updateCalendar(mine, { name: "Taken" }))).toBe(
        "CALENDAR_FORBIDDEN",
      );

      await s.as(alice);
      await calendar.setGrant(mine, bob.id, "viewer").orThrow();
      expect(await calendar.grants(mine).orThrow()).toEqual([
        { userId: bob.id, role: "viewer" },
      ]);

      const link = await s.value<{ token: string }>(
        "better_supabase.create_share_link($1, 'calendar_user', $2, 'view')",
        [org, alice.id],
      );

      await s.as("anon");
      const ics = await calendar.userFeed(link.token).orThrow();
      expect(ics).toContain("SUMMARY:Physio");
      expect(ics).toContain("RDATE:20260305T090000Z");

      await s.asRole(bob);
      expect(
        await s.hint(
          "better_supabase.create_share_link($1, 'calendar_user', $2, 'view')",
          [org, alice.id],
        ),
      ).toBe("SHARE_SUBJECT_NOT_FOUND");
      expect(await calendar.occurrences([mine], range).orThrow()).toEqual([]);
    } finally {
      await s.close();
    }
  });

  it("keeps rules and dates in an app's own tables", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      await s.client.query(APP);

      await s.install(["organizations", "calendar"], {
        modules: {
          calendar: {
            schema: "calendar_adopt_app",
            tables: {
              calendars: "cal_app.calendars",
              events: "cal_app.events",
              attendees: null,
              workingHours: null,
              rules: "cal_app.event_rules",
              recurrenceDates: "cal_app.event_dates",
            },
            columns: {
              calendars: {
                tenant: "organization_id",
                tz: "timezone",
                color: null,
                ownerType: null,
                ownerId: "owner_user_id",
              },
              events: {
                tenant: "organization_id",
                tz: "timezone",
                rrule: null,
                exdates: null,
                rdates: null,
                description: null,
                location: null,
                subjectType: null,
                subjectId: null,
                color: null,
                kind: null,
                transparency: null,
                autoDecline: null,
                visibility: null,
                owner: null,
              },
              rules: {
                tenant: null,
                rrule: null,
                freq: "frequency",
                interval: "every",
                count: "occurrences",
                until: "ends_at",
                byDay: "weekdays",
                byMonthDay: null,
                byMonth: null,
                bySetPos: null,
              },
              recurrenceDates: { tenant: null, at: "occurs_at" },
            },
            values: {
              calendars: {
                visibility: { shared: "team", private: "personal" },
                ownerId: {},
              },
              rules: {
                freq: {
                  DAILY: "daily",
                  WEEKLY: "weekly",
                  MONTHLY: "monthly",
                  YEARLY: "yearly",
                },
              },
              recurrenceDates: { kind: { rdate: "extra", exdate: "skip" } },
            },
            options: { recurrence: "table", access: true },
          },
        },
        ownTables: {
          "cal_app.calendars": "app.sql",
          "cal_app.events": "app.sql",
          "cal_app.event_rules": "app.sql",
          "cal_app.event_dates": "app.sql",
        },
      });

      const org = await s.organization(owner);

      const calendar = createCalendar({
        transport: sqlTransport(s.sql),
        schema: "calendar_adopt_app",
      });

      await s.as(owner);

      const { id } = await calendar
        .createCalendar(org, "Owner", { ownerId: owner.id })
        .orThrow();

      const series = await calendar
        .upsert(id, {
          title: "Review",
          startsAt: at("2026-03-02T09:00:00Z"),
          endsAt: at("2026-03-02T10:00:00Z"),
          rrule: "FREQ=WEEKLY;BYDAY=MO;COUNT=3",
          rdates: [at("2026-03-04T09:00:00Z")],
        })
        .orThrow();

      const [found] = await calendar.occurrences([id], range).orThrow();
      expect(found?.event.rrule).toBe("FREQ=WEEKLY;COUNT=3;BYDAY=MO");

      const occurrences = await calendar.occurrences([id], range).orThrow();
      await calendar.cancelOccurrence(occurrences[2]!).orThrow();

      expect(
        await s.rows<{ kind: string }>(
          "select kind::text as kind from cal_app.event_dates where event_id = $1 order by occurs_at",
          [series.id],
        ),
      ).toEqual([{ kind: "extra" }, { kind: "skip" }]);
    } finally {
      await s.close();
    }
  });
});
