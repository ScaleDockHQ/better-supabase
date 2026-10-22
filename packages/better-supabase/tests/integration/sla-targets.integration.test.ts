import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createDeals } from "../../src/blocks/deals/index.ts";
import { createGoals } from "../../src/blocks/goals/index.ts";
import { createSla } from "../../src/blocks/sla/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const TABLE = `create schema if not exists sla_it;
create table sla_it.tickets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  subject text not null,
  priority text not null default 'normal',
  status text not null default 'open'
);
alter table sla_it.tickets enable row level security;
create policy tickets_member on sla_it.tickets for all to authenticated
  using (organization_id in (select better_supabase.tenant_ids_with('sla.read')))
  with check (organization_id in (select better_supabase.tenant_ids_with('sla.read')));
grant usage on schema sla_it to authenticated;
grant select, insert, update on sla_it.tickets to authenticated;`;

const layout: BlockSqlLayout = {
  subjects: {
    ticket: { table: "sla_it.tickets", idType: "uuid" },
    ...withBlockSubjects({}, ["deals"], {}),
  },
  modules: {
    sla: {
      options: {
        businessHours: {
          timeZone: "Europe/Amsterdam",
          start: "09:00",
          end: "17:00",
          days: [1, 2, 3, 4, 5],
        },
        subjects: {
          ticket: {
            status: "status",
            priority: "priority",
            pause: ["waiting"],
            resolve: ["solved", "closed"],
          },
        },
      },
    },
  },
};

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "pipelines",
  "deals",
  "sla",
  "goals",
];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("service levels and targets", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("counts business hours and runs clocks off a ticket's status", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const agent = await s.user("agent");
      await s.client.query(TABLE);
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: agent });
      const transport = sqlTransport(s.sql);
      const sla = createSla({ transport, tenant: org });

      await s.as(owner);

      // Friday 16:00 in Amsterdam plus two working hours is Monday 10:00.
      const due = await sla
        .dueAt(Temporal.Instant.from("2026-10-16T14:00:00Z"), 120, true)
        .orThrow();

      expect(due.toString()).toBe("2026-10-19T08:00:00Z");
      expect(
        (
          await sla
            .dueAt(Temporal.Instant.from("2026-10-16T14:00:00Z"), 120, false)
            .orThrow()
        ).toString(),
      ).toBe("2026-10-16T16:00:00Z");

      await sla
        .savePolicy({
          subjectType: "ticket",
          name: "Normal",
          firstResponseMinutes: 240,
          nextResponseMinutes: 120,
          resolutionMinutes: 2880,
        })
        .orThrow();
      await sla
        .savePolicy({
          subjectType: "ticket",
          name: "Urgent",
          priority: "urgent",
          firstResponseMinutes: 30,
          resolutionMinutes: 240,
          warnAtPercent: 50,
        })
        .orThrow();
      expect(
        hint(
          await sla.savePolicy({
            subjectType: "ticket",
            name: "Dup",
            priority: "urgent",
            firstResponseMinutes: 1,
          }),
        ),
      ).toBe("SLA_POLICY_TAKEN");

      await s.asRole(agent);

      const [ticket] = await s.rows<{ id: string }>(
        "insert into sla_it.tickets (organization_id, subject) values ($1, 'Printer') returning id",
        [org],
      );

      await s.as(agent);
      const subject = { type: "ticket", id: ticket?.id ?? "" };
      let clocks = await sla.clocks(subject).orThrow();
      expect(
        clocks
          .map((clock) => `${clock.metric}:${clock.state}`)
          .toSorted((a, b) => a.localeCompare(b)),
      ).toEqual(["first_response:running", "resolution:running"]);

      await s.asRole(agent);
      await s.client.query(
        "update sla_it.tickets set priority = 'urgent' where id = $1",
        [subject.id],
      );
      await s.as(agent);
      clocks = await sla.clocks(subject).orThrow();
      const first = clocks.find((clock) => clock.metric === "first_response");
      expect(first?.dueAt.since(first.startedAt).total("minutes")).toBeCloseTo(
        30,
        0,
      );

      clocks = await sla.record(subject, "responded").orThrow();
      expect(
        clocks.find((clock) => clock.metric === "first_response")?.state,
      ).toBe("met");
      expect(clocks.some((clock) => clock.metric === "next_response")).toBe(
        false,
      );

      await s.asRole(agent);
      await s.client.query(
        "update sla_it.tickets set status = 'waiting' where id = $1",
        [subject.id],
      );
      await s.as(agent);
      expect(
        (await sla.clocks(subject).orThrow()).find(
          (clock) => clock.metric === "resolution",
        )?.state,
      ).toBe("paused");
      await s.asRole(agent);
      await s.client.query(
        "update sla_it.tickets set status = 'open' where id = $1",
        [subject.id],
      );
      await s.client.query(
        "update sla_it.tickets set status = 'solved' where id = $1",
        [subject.id],
      );
      await s.as(agent);
      expect(
        (await sla.clocks(subject).orThrow()).every(
          (clock) => clock.state === "met",
        ),
      ).toBe(true);

      await s.service();
      await s.client.query(
        "update better_supabase.sla_clocks set started_at = now() - interval '2 hours', due_at = now() - interval '1 minute', met_at = null where subject_id = $1 and metric = 'resolution'",
        [subject.id],
      );
      expect(await sla.check().orThrow()).toBe(1);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.outbox_events where type = 'sla.breached' and organization_id = $1)",
          [org],
        ),
      ).toBe(1);
      await s.as(agent);
      expect(
        hint(
          await sla.savePolicy({
            subjectType: "ticket",
            name: "X",
            firstResponseMinutes: 1,
          }),
        ),
      ).toBe("SLA_FORBIDDEN");
    } finally {
      await s.close();
    }
  });

  it("measures targets from won deals and a value the app keeps", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      await s.client.query(TABLE);
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      const transport = sqlTransport(s.sql);
      const targets = createGoals({ transport });
      const deals = createDeals({ transport });
      const today = Temporal.Now.plainDateISO();

      const quarter = {
        periodStart: today.subtract({ days: 30 }),
        periodEnd: today.add({ days: 60 }),
      };

      await s.as(owner);
      await targets
        .save(org, {
          name: "Rep quota",
          metric: "deals.won_amount",
          ownerId: rep.id,
          currency: "EUR",
          goal: 1_000_000n,
          ...quarter,
        })
        .orThrow();
      await targets
        .save(org, {
          name: "Team wins",
          metric: "deals.won_count",
          goal: 4n,
          ...quarter,
        })
        .orThrow();
      await targets
        .save(org, {
          name: "NPS responses",
          metric: "surveys.responses",
          goal: 50n,
          actual: 20n,
          ...quarter,
        })
        .orThrow();
      expect(
        hint(
          await targets.save(org, {
            name: "Bad",
            metric: "x",
            goal: 0n,
            ...quarter,
          }),
        ),
      ).toBe("TARGET_INVALID");

      await s.as(rep);

      const deal = await deals
        .create(org, {
          name: "Win",
          closeOn: today,
          amount: money(600_000n, "EUR"),
        })
        .orThrow();

      await deals.win(deal.id).orThrow();
      await deals
        .create(org, {
          name: "Open",
          closeOn: today,
          amount: money(900_000n, "EUR"),
        })
        .orThrow();

      const progress = await targets.progress(org).orThrow();
      expect(
        progress.map((target) => [
          target.name,
          target.progress,
          target.attainment,
        ]),
      ).toEqual([
        ["NPS responses", 20n, 0.4],
        ["Rep quota", 600_000n, 0.6],
        ["Team wins", 1n, 0.25],
      ]);
      expect(
        (await targets.progress(org, { ownerId: rep.id }).orThrow()).map(
          (target) => target.name,
        ),
      ).toEqual(["Rep quota"]);
      expect(
        await targets.progress(org, { on: today.add({ days: 365 }) }).orThrow(),
      ).toEqual([]);
      expect(
        hint(
          await targets.save(org, {
            name: "Mine",
            metric: "x",
            goal: 1n,
            ...quarter,
          }),
        ),
      ).toBe("TARGET_FORBIDDEN");
    } finally {
      await s.close();
    }
  });
});
