import { createBlocks, sqlTransport } from "better-supabase/blocks";
import { commentsBlock } from "better-supabase/blocks/comments";
import { createDeals } from "better-supabase/blocks/deals";
import { createPipelines } from "better-supabase/blocks/pipelines";
import { tagsBlock } from "better-supabase/blocks/tags";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Session } from "./stack.ts";

import { received, watching } from "./flow.ts";
import { crm } from "./recipes.ts";
import { dbUrl, reachable, withRecipe } from "./stack.ts";

const live = await reachable();

const STAGES = [
  { key: "lead", name: "Lead", category: "open" },
  { key: "qualified", name: "Qualified", category: "open" },
  { key: "won", name: "Won", category: "won" },
  { key: "lost", name: "Lost", category: "lost" },
] as const;

type StageKey = (typeof STAGES)[number]["key"];

/**
 * An organization with an owner and a member, a Sales pipeline the owner sets
 * up, and one deal in its Lead stage that the member watches. The owner watches
 * it too, as the deal's owner.
 */
async function salesWorkspace(s: Session) {
  const owner = await s.user("owner");
  const member = await s.user("member");
  const organizationId = await s.organization(owner, [member]);
  const transport = sqlTransport(s.sql);
  const pipelines = createPipelines({ transport });
  const deals = createDeals({ transport });

  await s.as(owner);

  const sales = await pipelines
    .save(organizationId, { subjectType: "deal", key: "sales", name: "Sales" })
    .orThrow();

  const stages = new Map<StageKey, string>();

  for (const stage of STAGES) {
    const saved = await pipelines.saveStage(sales.id, stage).orThrow();
    stages.set(stage.key, saved.id);
  }

  const stage = (key: StageKey): string => stages.get(key) ?? "";

  const deal = await deals
    .create(organizationId, {
      name: "Acme renewal",
      closeOn: Temporal.PlainDate.from("2026-12-31"),
      pipelineId: sales.id,
      stageId: stage("lead"),
    })
    .orThrow();

  await s.watch(member, organizationId, "deal", deal.id);
  await s.as(owner);

  return {
    owner,
    member,
    organizationId,
    pipelines,
    deals,
    pipelineId: sales.id,
    dealId: deal.id,
    stage,
  };
}

describe.skipIf(!live)("CRM recipe", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });

  afterAll(() => pool.end());

  it("notifies a deal's watchers about comments, tags and stage moves", async () => {
    await withRecipe(pool, crm, async (s) => {
      const { owner, member, organizationId, deals, dealId, stage } =
        await salesWorkspace(s);

      const watchers = await watching(s);

      const { comments, tags } = createBlocks(
        { transport: sqlTransport(s.sql), tenant: organizationId },
        { comments: commentsBlock, tags: tagsBlock },
      );

      await s.as(owner);
      const deal = { type: "deal", id: dealId };
      await comments.create(deal, { body: "Sent the renewal quote" }).orThrow();
      const hot = await tags.create("deal", "Hot").orThrow();
      await tags.tag(deal, hot.id).orThrow();

      const moved = await deals
        .update([{ dealId, field: "stageId", value: stage("qualified") }])
        .orThrow();

      expect(moved.rejected).toEqual([]);

      // Comments and pipelines notify the watchers themselves; the tag
      // reaches them through the outbox.
      expect(await watchers.relay()).toBeGreaterThanOrEqual(3);
      expect(await received(s, member, dealId)).toEqual([
        "comment.posted",
        "pipeline.stage_changed",
        "subject.tagged",
      ]);
      // The pipelines trigger builds its notification after switching to the
      // service role's claims, so it names no actor and the mover hears of
      // their own move.
      expect(await received(s, owner, dealId)).toEqual([
        "pipeline.stage_changed",
      ]);
    });
  });

  it("refuses a stage move the pipeline's transitions do not allow", async () => {
    await withRecipe(pool, crm, async (s) => {
      const { pipelines, deals, pipelineId, dealId, stage } =
        await salesWorkspace(s);

      await pipelines
        .setTransitions(pipelineId, [
          { from: stage("lead"), to: stage("qualified") },
          { from: stage("lead"), to: stage("lost") },
          { from: stage("qualified"), to: stage("won") },
          { from: stage("qualified"), to: stage("lost") },
          { from: stage("lost"), to: stage("lead") },
        ])
        .orThrow();

      const jump = await deals
        .update([{ dealId, field: "stageId", value: stage("won") }])
        .orThrow();

      expect(jump.accepted).toEqual([]);
      expect(jump.rejected.map((change) => change.hint)).toEqual([
        "PIPELINE_TRANSITION_INVALID",
      ]);

      const early = await deals.win(dealId);

      expect(early.ok ? undefined : early.error.hint).toBe(
        "PIPELINE_TRANSITION_INVALID",
      );

      const step = await deals
        .update([{ dealId, field: "stageId", value: stage("qualified") }])
        .orThrow();

      expect(step.rejected).toEqual([]);
      expect((await deals.win(dealId).orThrow()).outcome).toBe("won");
    });
  });
});
