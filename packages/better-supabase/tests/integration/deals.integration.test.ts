import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createActivities } from "../../src/blocks/activities/index.ts";
import { createContacts } from "../../src/blocks/contacts/index.ts";
import { createDeals } from "../../src/blocks/deals/index.ts";
import { createPipelines } from "../../src/blocks/pipelines/index.ts";
import { createRank } from "../../src/blocks/rank/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const eur = (amount: bigint) => money(amount, "EUR");

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "state-machine",
  "rank",
  "contacts",
  "activities",
  "pipelines",
  "deals",
];

const layout = (readAll = true): BlockSqlLayout => ({
  subjects: withBlockSubjects({}, ["contacts", "deals"], {}),
  modules: { deals: { options: { readAll } } },
});

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const day = (text: string): Temporal.PlainDate => Temporal.PlainDate.from(text);

describe.skipIf(!live)("deals", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("runs a deal from qualified to won with edits, lines and a forecast", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const other = await s.user("other");
      await s.install(MODULES, layout());
      const org = await s.organization(owner, { member: rep, member2: other });
      const transport = sqlTransport(s.sql);
      const deals = createDeals({ transport });
      const parties = createContacts({ transport });
      const pipelines = createPipelines({ transport });

      await s.as(rep);

      const acme = await parties
        .saveCompany({ organizationId: org, input: { name: "Acme" } })
        .orThrow();

      const ada = await parties
        .savePerson({ organizationId: org, input: { name: "Ada" } })
        .orThrow();

      const deal = await deals
        .create({
          organizationId: org,
          input: {
            name: "Growth plan, 60 seats",
            closeOn: day("2026-11-30"),
            amount: eur(4_800_000n),
            company: { type: "company", id: acme.id },
            motion: "new_logo",
            forecast: "pipeline",
          },
          contacts: [
            { type: "person", id: ada.id, role: "Champion", primary: true },
          ],
        })
        .orThrow();

      expect(deal).toMatchObject({
        identifier: "DEAL-1",
        currency: "EUR",
        ownerId: rep.id,
        outcome: "open",
        company: { type: "company", id: acme.id },
        contacts: [
          { type: "person", id: ada.id, role: "Champion", primary: true },
        ],
      });

      const [pipeline] = await pipelines
        .list({ organizationId: org, subjectType: "deal" })
        .orThrow();

      expect(pipeline?.stages.map((stage) => stage.key)).toEqual([
        "qualified",
        "discovery",
        "proposal",
        "negotiation",
        "closed_won",
        "closed_lost",
      ]);
      expect(deal.stageId).toBe(pipeline?.stages[0]?.id);
      const proposal = pipeline?.stages[2]?.id ?? "";

      const edits = await deals
        .update({
          changes: [
            { dealId: deal.id, field: "stageId", value: proposal },
            { dealId: deal.id, field: "closeOn", value: day("2026-12-15") },
            { dealId: deal.id, field: "forecast", value: "commit" },
            { dealId: deal.id, field: "motion", value: "upsell" },
            { dealId: deal.id, field: "openedOn", value: "2020-01-01" },
          ],
        })
        .orThrow();

      expect(edits.accepted.map((item) => item.field)).toEqual([
        "stageId",
        "closeOn",
        "forecast",
      ]);
      expect(edits.rejected.map((item) => item.hint)).toEqual([
        "DEAL_MOTION_INVALID",
        "DEAL_FIELD_UNKNOWN",
      ]);

      const wrongCurrency = await deals
        .update({
          changes: [
            { dealId: deal.id, field: "amount", value: money(5n, "USD") },
          ],
        })
        .orThrow();

      expect(wrongCurrency.rejected.map((item) => item.hint)).toEqual([
        "DEAL_CURRENCY_MISMATCH",
      ]);

      const totals = await deals
        .setLines({
          dealId: deal.id,
          lines: [
            {
              description: "Pro, annual seat",
              quantity: 60,
              unitAmount: eur(80_000n),
              discountBps: 1000,
            },
            {
              description: "Onboarding",
              unitAmount: eur(250_000n),
              taxRateBps: 2100,
            },
          ],
        })
        .orThrow();

      expect(totals).toEqual({
        listTotal: eur(5_050_000n),
        discountTotal: eur(480_000n),
        subtotal: eur(4_570_000n),
        taxTotal: eur(52_500n),
        total: eur(4_622_500n),
      });
      await deals
        .update({
          changes: [
            { dealId: deal.id, field: "amountSource", value: "line_items" },
          ],
        })
        .orThrow();
      await deals
        .setLines({
          dealId: deal.id,
          lines: [
            { description: "Pro", quantity: 10, unitAmount: eur(100_000n) },
          ],
        })
        .orThrow();

      const health = await deals.health(pipeline?.id ?? "").orThrow();
      expect(health).toEqual([
        expect.objectContaining({
          slipped: true,
          noNextStep: true,
          overdue: false,
        }),
      ]);
      await createActivities({ transport })
        .log({
          organizationId: org,
          input: {
            type: "call",
            title: "Pricing call",
            dueAt: Temporal.Now.instant().add({ hours: 3 }),
          },
          subjects: [{ type: "deal", id: deal.id }],
        })
        .orThrow();
      expect(
        (await deals.health(pipeline?.id ?? "").orThrow())[0]?.noNextStep,
      ).toBe(false);

      const forecast = await deals
        .forecast({
          organizationId: org,
          period: {
            since: day("2026-10-01"),
            until: day("2026-12-31"),
            currency: "EUR",
            target: eur(2_000_000n),
          },
        })
        .orThrow();

      expect(forecast).toMatchObject({
        commit: eur(1_000_000n),
        won: eur(0n),
        attainment: 0.5,
        gap: eur(1_000_000n),
      });
      expect(forecast.owners).toEqual([
        expect.objectContaining({ ownerId: rep.id, commit: eur(1_000_000n) }),
      ]);

      const won = await deals
        .win({ dealId: deal.id, note: "Order form signed" })
        .orThrow();

      expect(won).toMatchObject({ outcome: "won", note: "Order form signed" });
      expect(won.closedAt).toBeDefined();

      const closedEdit = await deals
        .update({
          changes: [{ dealId: deal.id, field: "forecast", value: "omit" }],
        })
        .orThrow();

      expect(closedEdit.rejected[0]?.hint).toBe("DEAL_FORECAST_CLOSED");

      const wonForecast = await deals
        .forecast({
          organizationId: org,
          period: {
            since: day("2026-01-01"),
            until: day("2026-12-31"),
            currency: "EUR",
          },
        })
        .orThrow();

      expect(wonForecast.won).toEqual(eur(1_000_000n));
      const reopened = await deals.reopen({ dealId: deal.id }).orThrow();
      expect(reopened).toMatchObject({
        outcome: "open",
        stageId: pipeline?.stages[0]?.id,
      });
      expect(reopened.closedAt).toBeUndefined();

      const lost = await deals
        .lose({ dealId: deal.id, reason: "Budget" })
        .orThrow();

      expect(lost).toMatchObject({ outcome: "lost", lostReason: "Budget" });

      const outcomes = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and type like 'deal.%' order by created_at",
        [org],
      );

      expect(outcomes.map((row) => row.type)).toEqual(
        expect.arrayContaining([
          "deal.created",
          "deal.updated",
          "deal.closed",
          "deal.reopened",
        ]),
      );
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.notification_subscriptions where subject_type = 'deal' and subject_id = $1 and user_id = $2)",
          [deal.id, rep.id],
        ),
      ).toBe(1);
    } finally {
      await s.close();
    }
  });

  it("locks deals, scopes them to their team and moves them on the board", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const peer = await s.user("peer");
      await s.install(MODULES, layout(false));
      const org = await s.organization(owner, { member: rep, member2: peer });
      const transport = sqlTransport(s.sql);
      const deals = createDeals({ transport });

      await s.as(rep);

      const deal = await deals
        .create({
          organizationId: org,
          input: {
            name: "Renewal",
            closeOn: day("2026-12-01"),
            currency: "USD",
          },
        })
        .orThrow();

      await s.asRole(peer);
      expect(
        await s.rows("select 1 from better_supabase.deals where id = $1", [
          deal.id,
        ]),
      ).toHaveLength(0);
      await s.as(rep);
      await deals
        .setMembers({
          dealId: deal.id,
          members: [{ userId: peer.id, role: "SE" }],
        })
        .orThrow();
      await s.asRole(peer);
      expect(
        await s.rows("select 1 from better_supabase.deals where id = $1", [
          deal.id,
        ]),
      ).toHaveLength(1);

      await s.service();
      await s.client.query(
        "update better_supabase.deals set locked = true where id = $1",
        [deal.id],
      );
      await s.as(rep);

      const locked = await deals
        .update({
          changes: [
            { dealId: deal.id, field: "amount", value: money(5n, "USD") },
            { dealId: deal.id, field: "note", value: "Waiting for PO" },
          ],
        })
        .orThrow();

      expect(locked.rejected.map((item) => item.hint)).toEqual(["DEAL_LOCKED"]);
      expect(locked.accepted.map((item) => item.field)).toEqual(["note"]);
      expect(
        hint(
          await deals.setLines({
            dealId: deal.id,
            lines: [{ description: "x", unitAmount: eur(1n) }],
          }),
        ),
      ).toBe("LINES_RECORD_INVALID");

      await s.service();
      await s.client.query(
        "update better_supabase.deals set locked = false where id = $1",
        [deal.id],
      );
      await s.as(rep);

      const second = await deals
        .create({
          organizationId: org,
          input: {
            name: "Upsell",
            closeOn: day("2026-12-02"),
            amount: money(9_007_199_254_740_993n, "USD"),
          },
        })
        .orThrow();

      expect(second.amount).toEqual(money(9_007_199_254_740_993n, "USD"));
      expect(
        await s.value<string>(
          "(select amount::text from better_supabase.deals where id = $1)",
          [second.id],
        ),
      ).toBe("9007199254740993");

      const discovery = await s.value<string>(
        "(select id::text from better_supabase.pipeline_stages where pipeline_id = $1 and key = 'discovery')",
        [deal.pipelineId],
      );

      await createRank({ transport })
        .move({
          subjectType: "deal",
          subjectId: second.id,
          target: { group: discovery },
        })
        .orThrow();
      await createRank({ transport })
        .move({
          subjectType: "deal",
          subjectId: deal.id,
          target: { previous: second.id, group: discovery },
        })
        .orThrow();
      expect(
        (
          await s.rows<{ id: string }>(
            'select id from better_supabase.deals where stage_id = $1 order by rank collate "C"',
            [discovery],
          )
        ).map((row) => row.id),
      ).toEqual([second.id, deal.id]);

      expect(
        hint(
          await deals.create({
            organizationId: org,
            input: {
              name: "x",
              closeOn: day("2026-12-01"),
              company: { type: "company", id: crypto.randomUUID() },
            },
          }),
        ),
      ).toBe("DEAL_COMPANY_FORBIDDEN");
      await s.as(peer);
      expect(await deals.remove(deal.id).orThrow()).toBe(false);
      await s.as(owner);
      expect(await deals.remove(deal.id).orThrow()).toBe(true);
    } finally {
      await s.close();
    }
  });
});
