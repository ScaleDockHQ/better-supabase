import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { createApprovals } from "../../src/blocks/approvals/index.ts";
import { createStateMachine } from "../../src/blocks/state-machine/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

// role_in reads memberships, which the organizations module creates after this runs.
const TABLES = `set local check_function_bodies = off;
create schema sm_it;
create table sm_it.quotes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  status text
);
create function sm_it.role_in(org uuid) returns text
language sql stable security definer set search_path = '' as $$
  select m.role from better_supabase.memberships m
  where m.organization_id = org and m.user_id = auth.uid()
$$;
grant execute on function sm_it.role_in(uuid) to authenticated;
alter table sm_it.quotes enable row level security;
create policy quotes_read on sm_it.quotes for select to authenticated
  using (sm_it.role_in(organization_id) is not null);
create policy quotes_update on sm_it.quotes for update to authenticated
  using (sm_it.role_in(organization_id) in ('owner', 'admin', 'member'));
grant usage on schema sm_it to authenticated;
grant select, update on sm_it.quotes to authenticated;`;

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "state-machine",
  "approvals",
];

const layout = (owner: string): ModuleLayout => ({
  subjects: { quote: { table: "sm_it.quotes", idType: "uuid" } },
  modules: {
    "state-machine": {
      options: {
        machines: {
          quote: {
            column: "status",
            initial: "draft",
            stages: true,
            lifecycle: true,
            version: 2,
            order: ["draft", "sent", "accepted"],
            flags: ["urgent"],
            transitions: { draft: ["sent", "void"], sent: ["accepted"] },
            requiresApproval: { sent: ["accepted"] },
          },
        },
      },
    },
    approvals: {
      options: {
        policies: {
          quote: {
            accept: {
              steps: [{ approvers: { users: [owner] } }],
              run: { transition: "accepted" },
            },
          },
        },
      },
    },
  },
});

describe.skipIf(!live)("state machine", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("transitions only records the caller may update, and keeps a lifecycle", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const viewer = await s.user("viewer");
      const outsider = await s.user("outsider");
      await s.install(MODULES, layout(owner.id));
      const tenant = await s.organization(owner, { member, viewer });
      await s.organization(outsider);
      await s.service();

      const quote = (
        await s.rows<{ id: string }>(
          "insert into sm_it.quotes (organization_id) values ($1) returning id",
          [tenant],
        )
      )[0]!.id;

      const machine = createStateMachine<"quote">({
        transport: sqlTransport(s.sql),
      });

      const subject = { type: "quote", id: quote } as const;

      const errorOf = async (
        result: PromiseLike<
          { ok: true } | { ok: false; error: { hint?: string | undefined } }
        >,
      ) => {
        const settled = await result;

        return settled.ok ? "ok" : settled.error.hint;
      };

      await s.asRole(outsider);
      expect(
        await s.hint("better_supabase.transition('quote', $1, 'sent', null)", [
          quote,
        ]),
      ).toBe("STATE_SUBJECT_NOT_FOUND");
      expect(await errorOf(machine.state(subject))).toBe(
        "STATE_SUBJECT_NOT_FOUND",
      );

      await s.asRole(viewer);
      expect(
        await s.hint("better_supabase.transition('quote', $1, 'sent', null)", [
          quote,
        ]),
      ).toBe("STATE_SUBJECT_NOT_FOUND");
      expect(await errorOf(machine.pause(subject, { reason: "look" }))).toBe(
        "STATE_SUBJECT_NOT_FOUND",
      );
      expect((await machine.state(subject).orThrow()).status).toBe("draft");

      await s.asRole(member);
      expect(await machine.transition(subject, "sent", "ready").orThrow()).toBe(
        true,
      );
      const sent = await machine.state(subject).orThrow();
      expect(sent).toMatchObject({
        status: "sent",
        step: 2,
        steps: 3,
        progress: 0.5,
        version: 2,
        paused: false,
      });

      expect(
        await machine.pause(subject, { reason: "client away" }).orThrow(),
      ).toBe(true);
      expect((await machine.state(subject).orThrow()).pauseReason).toBe(
        "client away",
      );
      expect(await machine.resume(subject).orThrow()).toBe(true);
      expect(await machine.resume(subject).orThrow()).toBe(false);

      expect(await machine.setFlag(subject, "urgent", true).orThrow()).toBe(
        true,
      );
      expect(await machine.setFlag(subject, "urgent", true).orThrow()).toBe(
        false,
      );
      expect(await errorOf(machine.setFlag(subject, "vip", true))).toBe(
        "STATE_FLAG_UNKNOWN",
      );
      expect((await machine.state(subject).orThrow()).flags).toEqual([
        "urgent",
      ]);

      const history = await machine.history(subject).orThrow();
      expect(history.map((change) => [change.from, change.to])).toEqual([
        ["draft", "sent"],
      ]);
      expect(history[0]?.reason).toBe("ready");
      const stages = await machine.stages(subject).orThrow();
      expect(stages.map((stage) => stage.label)).toEqual(["draft", "sent"]);
      expect(stages[0]?.clearedAt).toBeDefined();

      await s.asRole(viewer);
      expect(await machine.history(subject).orThrow()).toHaveLength(1);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.subject_lifecycles)",
        ),
      ).toBe(1);
      await s.asRole(outsider);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.status_history)",
        ),
      ).toBe(0);

      await s.service();

      const types = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 order by position",
        [tenant],
      );

      expect(types.map((row) => row.type)).toEqual(
        expect.arrayContaining([
          "status.changed",
          "status.paused",
          "status.resumed",
          "status.flagged",
        ]),
      );

      await s.asRole(member);
      expect(
        await s.hint(
          "better_supabase.transition('quote', $1, 'accepted', null)",
          [quote],
        ),
      ).toBe("STATE_APPROVAL_REQUIRED");

      const approvals = createApprovals({
        transport: sqlTransport(s.sql),
        tenant,
      });

      const request = await approvals
        .request(subject, { action: "accept" })
        .orThrow();

      await s.asRole(owner);
      await approvals.approve(request.id).orThrow();
      await s.service();
      expect(
        await s.value<string>(
          "(select status from sm_it.quotes where id = $1)",
          [quote],
        ),
      ).toBe("accepted");
    } finally {
      await s.close();
    }
  });

  it("refuses transitions while paused and clears a pause that has ended", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      const owner = await s.user("owner");
      await s.install(MODULES, layout(owner.id));
      const tenant = await s.organization(owner);
      await s.service();

      const quote = (
        await s.rows<{ id: string }>(
          "insert into sm_it.quotes (organization_id) values ($1) returning id",
          [tenant],
        )
      )[0]!.id;

      await s.asRole(owner);
      expect(
        await s.hint(
          "better_supabase.pause_lifecycle('quote', $1, now() - interval '1 minute', null)",
          [quote],
        ),
      ).toBe("STATE_PAUSE_INVALID");
      await s.value(
        "better_supabase.pause_lifecycle('quote', $1, null, 'hold')",
        [quote],
      );
      expect(
        await s.hint("better_supabase.transition('quote', $1, 'sent', null)", [
          quote,
        ]),
      ).toBe("STATE_PAUSED");

      await s.service();
      await s.client.query(
        "update better_supabase.subject_lifecycles set paused_until = now() - interval '1 second' where subject_id = $1",
        [quote],
      );
      await s.asRole(owner);
      expect(
        await s.value<boolean>(
          "better_supabase.transition('quote', $1, 'sent', null)",
          [quote],
        ),
      ).toBe(true);

      const state = await s.value<{ paused: boolean }>(
        "better_supabase.status_state('quote', $1)",
        [quote],
      );

      expect(state.paused).toBe(false);
    } finally {
      await s.close();
    }
  });
});
