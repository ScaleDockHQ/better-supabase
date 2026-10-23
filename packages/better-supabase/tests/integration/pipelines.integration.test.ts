import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const TABLE = `create schema if not exists pipe_it;
create table pipe_it.deals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null,
  pipeline_id uuid,
  stage_id uuid,
  stage_entered_at timestamptz,
  outcome text not null default 'open',
  amount bigint,
  currency char(3),
  probability smallint,
  owner_id uuid,
  rank text collate "C" not null default 'V'
);
alter table pipe_it.deals enable row level security;
create policy deals_members on pipe_it.deals for all to authenticated
  using (organization_id in (select better_supabase.tenant_ids_with('pipelines.read')))
  with check (organization_id in (select better_supabase.tenant_ids_with('pipelines.read')));
grant usage on schema pipe_it to authenticated;
grant select, insert, update on pipe_it.deals to authenticated;`;

const layout: BlockSqlLayout = {
  subjects: {
    deal: {
      table: "pipe_it.deals",
      idType: "uuid",
      rank: { column: "rank", group: "stage_id" },
    },
  },
  modules: {
    pipelines: {
      on: {
        deal: {
          enteredAt: "stage_entered_at",
          amount: "amount",
          currency: "currency",
          probability: "probability",
          owner: "owner_id",
          categories: { open: "open", won: "success", lost: "failure" },
          status: {
            column: "outcome",
            values: { open: "open", won: "won", lost: "lost" },
          },
          stages: [
            { key: "lead", name: "Lead", category: "open", probability: 10 },
            {
              key: "proposal",
              name: "Proposal",
              category: "open",
              probability: 50,
            },
            { key: "won", name: "Won", category: "won", probability: 100 },
            { key: "lost", name: "Lost", category: "lost", probability: 0 },
          ],
        },
      },
    },
    "state-machine": {
      options: {
        machines: {
          deal_outcome: {
            table: "pipe_it.deals",
            column: "outcome",
            tenant: "organization_id",
            initial: "open",
            transitions: {
              open: ["won", "lost"],
              won: ["open"],
              lost: ["open"],
            },
          },
        },
      },
    },
  },
};

const MODULES = [
  "organizations",
  "outbox",
  "subjects",
  "notifications",
  "state-machine",
  "rank",
  "pipelines",
];

interface Deal {
  readonly id: string;
  readonly pipeline_id: string;
  readonly stage_id: string;
  readonly outcome: string;
  readonly stage_entered_at: Date | null;
}

describe.skipIf(!live)("pipelines", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("runs a deal through its default pipeline", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const stranger = await s.user("stranger");
      await s.client.query(TABLE);
      await s.install(MODULES, layout);
      const tenant = await s.organization(owner, { member: rep });
      const other = await s.organization(stranger);

      await s.asRole(rep);

      const [deal] = await s.rows<Deal>(
        `insert into pipe_it.deals (organization_id, name, amount, currency, owner_id)
         values ($1, 'Acme', 120000, 'EUR', $2) returning *`,
        [tenant, rep.id],
      );

      expect(deal?.pipeline_id).toBeTruthy();
      expect(deal?.stage_entered_at).toBeInstanceOf(Date);

      const stages = await s.rows<{ id: string; key: string; outcome: string }>(
        `select id, key, outcome from better_supabase.pipeline_stages where pipeline_id = $1 order by rank collate "C"`,
        [deal?.pipeline_id],
      );

      expect(stages.map((stage) => stage.key)).toEqual([
        "lead",
        "proposal",
        "won",
        "lost",
      ]);
      expect(deal?.stage_id).toBe(stages[0]?.id);

      const stage = (key: string): string =>
        stages.find((item) => item.key === key)?.id ?? "";

      await s.client.query(
        "update pipe_it.deals set stage_id = $1 where id = $2",
        [stage("proposal"), deal?.id],
      );

      const board = await s.value<
        {
          key: string;
          count: number;
          totals: { currency: string; amount: string; weighted: string }[];
        }[]
      >("better_supabase.pipeline_board('deal', $1)", [deal?.pipeline_id]);

      expect(board.find((column) => column.key === "proposal")).toMatchObject({
        count: 1,
        totals: [{ currency: "EUR", amount: "120000", weighted: "60000" }],
      });

      await s.client.query(
        "update pipe_it.deals set stage_id = $1 where id = $2",
        [stage("won"), deal?.id],
      );
      expect(
        await s.value<string>(
          "(select outcome from pipe_it.deals where id = $1)",
          [deal?.id],
        ),
      ).toBe("won");

      const history = await s.rows<{
        stage_name: string;
        exited_at: Date | null;
      }>(
        `select stage_name, exited_at from better_supabase.pipeline_stage_history
         where subject_type = 'deal' and subject_id = $1::text order by entered_at, exited_at nulls last`,
        [deal?.id],
      );

      expect(history.map((row) => row.stage_name)).toEqual([
        "Lead",
        "Proposal",
        "Won",
      ]);
      expect(history.filter((row) => row.exited_at === null)).toHaveLength(1);

      const stats = await s.value<{ won: number; winRate: number }>(
        "better_supabase.pipeline_stats($1, now() - interval '1 day', now() + interval '1 day')",
        [deal?.pipeline_id],
      );

      expect(stats).toMatchObject({ won: 1, winRate: 1 });

      const watching = await s.value<number>(
        `(select count(*)::int from better_supabase.notification_subscriptions
          where subject_type = 'deal' and subject_id = $1::text and user_id = $2)`,
        [deal?.id, rep.id],
      );

      expect(watching).toBe(1);

      await s.asRole(stranger);
      expect(
        await s.hint("better_supabase.default_pipeline($1, 'deal', null)", [
          other,
        ]),
      ).toMatch(/permission denied/);
      expect(
        await s.rows(
          "select 1 from better_supabase.pipeline_stage_history where subject_id = $1::text",
          [deal?.id],
        ),
      ).toHaveLength(0);
    } finally {
      await s.close();
    }
  });

  it("refuses a stage from another pipeline and guards stage edits", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      await s.client.query(TABLE);
      await s.install(MODULES, layout);
      const tenant = await s.organization(owner, { member: rep });

      await s.asRole(rep);

      const [deal] = await s.rows<Deal>(
        "insert into pipe_it.deals (organization_id, name) values ($1, 'Globex') returning *",
        [tenant],
      );

      await s.as(owner);

      const second = await s.value<{ id: string }>(
        "better_supabase.save_pipeline($1, null, 'deal', 'renewals', 'Renewals', null, false)",
        [tenant],
      );

      const renewalStage = await s.value<{ id: string }>(
        "better_supabase.save_pipeline_stage($1, null, 'due', 'Due', 'open', 30, 14, null, null)",
        [second.id],
      );

      expect(
        await s.hint(
          "better_supabase.save_pipeline_stage($1, null, 'odd', 'Odd', 'maybe', null, null, null, null)",
          [second.id],
        ),
      ).toBe("PIPELINE_CATEGORY_UNKNOWN");

      await s.asRole(rep);
      expect(
        await s.rows("select id from pipe_it.deals where id = $1", [deal?.id]),
      ).toHaveLength(1);
      expect(
        await s.hint("update pipe_it.deals set stage_id = $1 where id = $2", [
          renewalStage.id,
          deal?.id,
        ]),
      ).toBe("PIPELINE_STAGE_INVALID");
      await s.client.query(
        "update pipe_it.deals set pipeline_id = $1, stage_id = $2 where id = $3",
        [second.id, renewalStage.id, deal?.id],
      );
      expect(
        await s.hint(
          "better_supabase.save_pipeline($1, null, 'deal', 'x', 'X', null, false)",
          [tenant],
        ),
      ).toBe("PIPELINE_FORBIDDEN");

      await s.as(owner);
      expect(
        await s.hint("better_supabase.archive_pipeline_stage($1)", [
          renewalStage.id,
        ]),
      ).toBe("PIPELINE_STAGE_IN_USE");
      await s.value("better_supabase.set_pipeline_transitions($1, $2::jsonb)", [
        second.id,
        JSON.stringify([]),
      ]);

      const health = await s.value<{ daysInStage: number; rotting: boolean }[]>(
        "better_supabase.pipeline_health($1)",
        [second.id],
      );

      expect(health).toEqual([
        expect.objectContaining({ daysInStage: 0, rotting: false }),
      ]);
    } finally {
      await s.close();
    }
  });

  it("moves a deal on the board into a uuid stage through rank", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      await s.client.query(TABLE);
      await s.install(MODULES, layout);
      const tenant = await s.organization(owner);
      await s.as(owner);

      const [deal] = await s.rows<Deal>(
        "insert into pipe_it.deals (organization_id, name) values ($1, 'Initech') returning *",
        [tenant],
      );

      const proposal = await s.value<string>(
        "(select id from better_supabase.pipeline_stages where pipeline_id = $1 and key = 'proposal')",
        [deal?.pipeline_id],
      );

      await s.value(
        "better_supabase.move('deal', $1::text, null, null, $2::text)",
        [deal?.id, proposal],
      );
      expect(
        await s.value<string>(
          "(select stage_id::text from pipe_it.deals where id = $1)",
          [deal?.id],
        ),
      ).toBe(proposal);
    } finally {
      await s.close();
    }
  });
});
