import { describe, expect, it } from "vitest";

import { createPipelines } from "../../../src/blocks/pipelines/index.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];
  return {
    calls,
    call(schema: string, fn: string, args: Record<string, unknown>) {
      expect(schema).toBe("better_supabase");
      calls.push([fn, args]);
      const result = results[fn];
      if (!result) return Promise.reject(new Error(`unexpected ${fn}`));
      return Promise.resolve(result(args));
    },
  };
}

const STAGE = {
  id: "s1",
  pipeline_id: "p1",
  key: "lead",
  system_key: "lead",
  name: "Lead",
  color: null,
  rank: "V",
  category: "open",
  outcome: "open",
  probability: 10,
  rotting_after_days: 14,
  wip_limit: null,
};
const PIPELINE = {
  id: "p1",
  tenant_id: "o",
  subject_type: "deal",
  scope_id: null,
  key: "default",
  name: "Default",
  rank: "V",
  is_default: true,
};

describe("pipelines block", () => {
  it("lists pipelines with their stages", async () => {
    const t = transport({
      list_pipelines: () => [{ ...PIPELINE, stages: [STAGE] }],
    });
    const pipelines = createPipelines({ transport: t });
    const [pipeline] = await pipelines.list("o", "deal").orThrow();
    expect(pipeline).toEqual({
      id: "p1",
      organizationId: "o",
      subjectType: "deal",
      key: "default",
      name: "Default",
      rank: "V",
      isDefault: true,
      fields: {},
      stages: [
        {
          id: "s1",
          pipelineId: "p1",
          key: "lead",
          systemKey: "lead",
          name: "Lead",
          rank: "V",
          category: "open",
          outcome: "open",
          probability: 10,
          rottingAfterDays: 14,
        },
      ],
    });
    expect(t.calls).toEqual([
      ["list_pipelines", { tenant: "o", subject_type: "deal" }],
    ]);
  });

  it("saves pipelines and stages with null for what the input leaves out", async () => {
    const t = transport({
      save_pipeline: () => PIPELINE,
      save_pipeline_stage: () => STAGE,
    });
    const pipelines = createPipelines({ transport: t });
    expect(
      (
        await pipelines
          .save("o", { subjectType: "deal", key: "default", name: "Default" })
          .orThrow()
      ).stages,
    ).toEqual([]);
    await pipelines
      .saveStage("p1", { key: "lead", name: "Lead", category: "open" })
      .orThrow();
    expect(t.calls).toEqual([
      [
        "save_pipeline",
        {
          tenant: "o",
          pipeline: null,
          subject_type: "deal",
          key: "default",
          name: "Default",
          scope_id: null,
          is_default: null,
        },
      ],
      [
        "save_pipeline_stage",
        {
          pipeline: "p1",
          stage: null,
          key: "lead",
          name: "Lead",
          category: "open",
          probability: null,
          rotting_after_days: null,
          wip_limit: null,
          color: null,
        },
      ],
    ]);
  });

  it("reads board totals as bigint minor units", async () => {
    const t = transport({
      pipeline_board: () => [
        {
          stageId: "s1",
          key: "lead",
          name: "Lead",
          color: null,
          category: "open",
          outcome: "open",
          probability: 10,
          wipLimit: 2,
          count: 3,
          overLimit: true,
          totals: [
            { currency: "EUR", amount: "9007199254740993", weighted: "100" },
          ],
        },
      ],
    });
    const [column] = await createPipelines({ transport: t })
      .board("deal", "p1", { owner: "u1" })
      .orThrow();
    expect(column).toMatchObject({
      count: 3,
      overLimit: true,
      wipLimit: 2,
      totals: [{ currency: "EUR", amount: 9007199254740993n, weighted: 100n }],
    });
    expect(t.calls[0]).toEqual([
      "pipeline_board",
      { subject_type: "deal", pipeline: "p1", owner: "u1" },
    ]);
  });

  it("passes stats windows as instants and reads health", async () => {
    const t = transport({
      pipeline_stats: () => ({
        won: 2,
        lost: 1,
        winRate: 0.6667,
        stages: [
          { stageId: "s1", key: "lead", entered: 3, averageSeconds: null },
        ],
      }),
      pipeline_health: () => [
        {
          subjectType: "deal",
          subjectId: "d1",
          stageId: "s1",
          enteredAt: "2026-10-01T00:00:00Z",
          daysInStage: 13,
          rotting: false,
        },
      ],
    });
    const pipelines = createPipelines({ transport: t });
    const since = Temporal.Instant.from("2026-10-01T00:00:00Z");
    const until = Temporal.Instant.from("2026-11-01T00:00:00Z");
    expect(await pipelines.stats("p1", { since, until }).orThrow()).toEqual({
      won: 2,
      lost: 1,
      winRate: 0.6667,
      stages: [{ stageId: "s1", key: "lead", entered: 3 }],
    });
    const [row] = await pipelines.health("p1").orThrow();
    expect(row?.enteredAt.equals(since)).toBe(true);
    expect(t.calls[0]?.[1]).toEqual({
      pipeline: "p1",
      since: "2026-10-01T00:00:00Z",
      until: "2026-11-01T00:00:00Z",
    });
  });

  it("checks rank neighbours before it reorders a stage", async () => {
    const t = transport({
      rank_pipeline_stage: () => true,
      set_pipeline_transitions: () => 1,
      archive_pipeline: () => true,
      archive_pipeline_stage: () => false,
    });
    const pipelines = createPipelines({ transport: t });
    expect(
      await pipelines
        .reorderStage("s1", { previous: "V", next: "k" })
        .orThrow(),
    ).toBe("c");
    expect(
      (await pipelines.reorderStage("s1", { previous: "k", next: "V" })).ok,
    ).toBe(false);
    expect(
      await pipelines
        .setTransitions("p1", [{ from: "s1", to: "s2" }])
        .orThrow(),
    ).toBe(1);
    expect(await pipelines.archive("p1").orThrow()).toBe(true);
    expect(await pipelines.archiveStage("s1").orThrow()).toBe(false);
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "rank_pipeline_stage",
      "set_pipeline_transitions",
      "archive_pipeline",
      "archive_pipeline_stage",
    ]);
    expect(t.calls[1]?.[1]).toEqual({
      pipeline: "p1",
      pairs: [{ from: "s1", to: "s2" }],
    });
  });

  it("runs hooks around a method", async () => {
    const seen: string[] = [];
    const t = transport({ archive_pipeline: () => true });
    const pipelines = createPipelines({
      transport: t,
      hooks: { archive: { before: ([id]) => void seen.push(`before ${id}`) } },
    });
    await pipelines.archive("p1").orThrow();
    expect(seen).toEqual(["before p1"]);
  });
});

describe("pipelines block, optional fields", () => {
  it("reads optional stage and column fields and empty stats", async () => {
    const t = transport({
      save_pipeline_stage: () => ({
        ...STAGE,
        system_key: null,
        color: "#f00",
        probability: null,
        rotting_after_days: null,
        wip_limit: 5,
      }),
      save_pipeline: () => ({ ...PIPELINE, scope_id: "job-1", stages: [] }),
      pipeline_board: () => [
        {
          stageId: "s1",
          key: "lead",
          name: "Lead",
          color: "#f00",
          category: "open",
          outcome: "open",
          probability: null,
          wipLimit: null,
          count: null,
          overLimit: false,
          totals: [{ currency: "EUR", amount: 5, weighted: null }],
        },
      ],
      pipeline_stats: () => ({
        won: null,
        lost: null,
        winRate: null,
        stages: [
          { stageId: "s1", key: "lead", entered: null, averageSeconds: 60 },
        ],
      }),
    });
    const pipelines = createPipelines({
      transport: t,
      logger: {
        error: () => undefined,
        warn: () => undefined,
        info: () => undefined,
        debug: () => undefined,
      },
      hooks: { board: { after: () => undefined } },
    });
    expect(
      await pipelines
        .saveStage("p1", {
          id: "s1",
          key: "lead",
          name: "Lead",
          category: "open",
          probability: 10,
          rottingAfterDays: 7,
          wipLimit: 5,
          color: "#f00",
        })
        .orThrow(),
    ).toMatchObject({ color: "#f00", wipLimit: 5 });
    expect(
      (
        await pipelines
          .save("o", {
            id: "p1",
            subjectType: "deal",
            key: "k",
            name: "N",
            scopeId: "job-1",
            isDefault: true,
          })
          .orThrow()
      ).scopeId,
    ).toBe("job-1");
    const [column] = await pipelines.board("deal", "p1").orThrow();
    expect(column).toMatchObject({
      color: "#f00",
      count: 0,
      totals: [{ currency: "EUR", amount: 5n, weighted: 0n }],
    });
    expect(column?.probability).toBeUndefined();
    const since = Temporal.Instant.from("2026-10-01T00:00:00Z");
    expect(
      await pipelines.stats("p1", { since, until: since }).orThrow(),
    ).toEqual({
      won: 0,
      lost: 0,
      stages: [{ stageId: "s1", key: "lead", entered: 0, averageSeconds: 60 }],
    });
  });
});
