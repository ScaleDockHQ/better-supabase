import { describe, expect, it } from "vitest";

import type { ScoreModelInput } from "../../../src/blocks/scores/index.ts";

import {
  createScores,
  scoresBlock,
  scoresEvents,
  scoresSection,
} from "../../../src/blocks/scores/index.ts";

const AT = "2026-10-22T10:00:00Z";

const TREE = {
  id: "g1",
  type: "group",
  combinator: "and",
  rules: [
    {
      id: "r1",
      type: "rule",
      path: ["stage"],
      operator: "is",
      value: "qualified",
    },
  ],
} as const;

const MODEL = {
  id: "m1",
  organizationId: "org-1",
  key: "lead",
  name: "Lead score",
  description: "Inbound",
  subjectType: "lead",
  rules: [
    { id: "q", label: "Qualified", conditions: TREE, points: 20 },
    { id: "r", conditions: TREE, points: "5" },
  ],
  metrics: [
    {
      id: "size",
      label: "Size",
      source: "field",
      field: "employees",
      weight: 0.5,
      cap: 25,
    },
    { id: "votes", source: "votes", weight: "2" },
  ],
  bands: [{ label: "hot", min: 50 }],
  enabled: true,
  version: 2,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const BARE_MODEL = {
  id: "m2",
  organizationId: "org-1",
  key: "health",
  name: "Health",
  description: null,
  subjectType: "party",
  rules: null,
  metrics: null,
  bands: null,
  enabled: false,
  version: null,
  createdBy: null,
  createdAt: AT,
  updatedAt: AT,
};

const SCORE = {
  id: "s1",
  organizationId: "org-1",
  modelId: "m1",
  modelKey: "lead",
  modelName: "Lead score",
  modelVersion: 2,
  subjectType: "lead",
  subjectId: "l1",
  score: 81.5,
  band: "hot",
  breakdown: {
    rules: [
      { id: "q", label: "Qualified", matched: true, points: 20 },
      { id: "r", matched: false, points: 0 },
    ],
    metrics: [
      { id: "size", label: "Size", value: 80, points: 25 },
      { id: "votes", value: null, points: 0 },
    ],
  },
  current: true,
  computedAt: AT,
};

const BARE_SCORE = {
  ...SCORE,
  id: "s0",
  modelName: null,
  band: null,
  breakdown: null,
  current: false,
  score: null,
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

describe("createScores", () => {
  it("saves, lists, reads and deletes models", async () => {
    const fake = fakeTransport({
      save_score_model: MODEL,
      list_score_models: [MODEL, BARE_MODEL],
      get_score_model: {
        ...MODEL,
        versions: [
          {
            version: 2,
            rules: MODEL.rules,
            metrics: [],
            bands: [],
            savedBy: "u1",
            savedAt: AT,
          },
          {
            version: 1,
            rules: [],
            metrics: [],
            bands: [],
            savedBy: null,
            savedAt: AT,
          },
        ],
      },
      delete_score_model: true,
    });

    const scores = createScores({ transport: fake.transport, tenant: "org-1" });

    const saved = await scores
      // SAFETY: an explicit `undefined` exercises the skip branch that
      // `exactOptionalPropertyTypes` rules out for typed callers.
      .saveModel({
        key: "lead",
        name: "Lead score",
        subjectType: "lead",
        description: undefined,
      } as unknown as ScoreModelInput)
      .orThrow();

    expect(saved).toMatchObject({
      key: "lead",
      description: "Inbound",
      version: 2,
      enabled: true,
      createdBy: "u1",
      bands: [{ label: "hot", min: 50 }],
    });
    expect(saved.rules).toEqual([
      { id: "q", label: "Qualified", conditions: TREE, points: 20 },
      { id: "r", conditions: TREE, points: 5 },
    ]);
    expect(saved.metrics).toEqual([
      {
        id: "size",
        label: "Size",
        source: "field",
        field: "employees",
        weight: 0.5,
        cap: 25,
      },
      { id: "votes", source: "votes" },
    ]);

    const [, bare] = await scores.models({ subjectType: "party" }).orThrow();

    expect(bare).toMatchObject({
      rules: [],
      metrics: [],
      bands: [],
      enabled: false,
      version: 0,
    });
    expect(bare?.description).toBeUndefined();
    expect(bare?.createdBy).toBeUndefined();

    const detail = await scores.model("m1").orThrow();

    expect(detail.versions.map((v) => [v.version, v.savedBy])).toEqual([
      [2, "u1"],
      [1, undefined],
    ]);

    await scores.models().orThrow();

    expect(await scores.deleteModel("m1").orThrow()).toBe(true);
    expect(fake.calls).toEqual([
      [
        "save_score_model",
        {
          tenant: "org-1",
          model: { key: "lead", name: "Lead score", subjectType: "lead" },
        },
      ],
      ["list_score_models", { tenant: "org-1", subject_type: "party" }],
      ["get_score_model", { model_id: "m1" }],
      ["list_score_models", { tenant: "org-1", subject_type: null }],
      ["delete_score_model", { model_id: "m1" }],
    ]);
  });

  it("returns not_found for a model the caller can't read", async () => {
    const scores = createScores({
      transport: fakeTransport({ get_score_model: null }).transport,
    });

    expect(await scores.model("m9")).toMatchObject({
      ok: false,
      error: { kind: "not_found", hint: "SCORES_MODEL_NOT_FOUND" },
    });
  });

  it("rejects a model whose rule has no filter tree", async () => {
    const fake = fakeTransport({
      list_score_models: [
        {
          ...MODEL,
          rules: [{ id: "x", conditions: { type: "rule" }, points: 1 }],
        },
      ],
    });

    const result = await createScores({
      transport: fake.transport,
      tenant: "org-1",
    }).models();

    expect(result.ok).toBe(false);
    expect(result.error?.message).toContain("a score rule's conditions are");
  });

  it("computes and reads scores", async () => {
    const fake = fakeTransport({
      compute_score: { ...SCORE, changed: true },
      subject_scores: [SCORE],
      score_history: [SCORE, BARE_SCORE],
      top_scores: [SCORE],
    });

    const scores = createScores({ transport: fake.transport, tenant: "org-1" });
    const lead = { type: "lead", id: "l1" };

    const computed = await scores
      .compute(
        "lead",
        lead,
        { stage: "qualified" },
        { timeZone: "Europe/Amsterdam" },
      )
      .orThrow();

    expect(computed).toMatchObject({
      changed: true,
      score: 81.5,
      band: "hot",
      subject: lead,
      modelName: "Lead score",
      current: true,
    });
    expect(computed.breakdown.metrics[1]).toEqual({
      id: "votes",
      value: null,
      points: 0,
    });
    expect(computed.computedAt.toString()).toBe(AT);

    await scores.compute("lead", lead, {}).orThrow();
    expect(await scores.list({ on: lead }).orThrow()).toHaveLength(1);

    const [, old] = await scores
      .history("lead", lead, { pageSize: 5 })
      .orThrow();

    expect(old).toMatchObject({
      score: 0,
      current: false,
      breakdown: { rules: [], metrics: [] },
    });
    expect(old?.band).toBeUndefined();
    expect(old?.modelName).toBeUndefined();

    await scores.history("lead", lead).orThrow();
    await scores
      .top("lead", { band: "hot", minScore: 10, pageSize: 3 })
      .orThrow();
    await scores.top("lead").orThrow();

    expect(fake.calls.map(([fn, args]) => [fn, args])).toEqual([
      [
        "compute_score",
        {
          tenant: "org-1",
          model_key: "lead",
          subject_type: "lead",
          subject_id: "l1",
          subject: { stage: "qualified" },
          time_zone: "Europe/Amsterdam",
        },
      ],
      [
        "compute_score",
        {
          tenant: "org-1",
          model_key: "lead",
          subject_type: "lead",
          subject_id: "l1",
          subject: {},
          time_zone: "UTC",
        },
      ],
      [
        "subject_scores",
        { tenant: "org-1", subject_type: "lead", subject_id: "l1" },
      ],
      [
        "score_history",
        {
          tenant: "org-1",
          model_key: "lead",
          subject_type: "lead",
          subject_id: "l1",
          page_size: 5,
        },
      ],
      [
        "score_history",
        {
          tenant: "org-1",
          model_key: "lead",
          subject_type: "lead",
          subject_id: "l1",
          page_size: null,
        },
      ],
      [
        "top_scores",
        {
          tenant: "org-1",
          model_key: "lead",
          band: "hot",
          min_score: 10,
          page_size: 3,
        },
      ],
      [
        "top_scores",
        {
          tenant: "org-1",
          model_key: "lead",
          band: null,
          min_score: null,
          page_size: null,
        },
      ],
    ]);
  });

  it("fails tenant-scoped calls without a tenant", async () => {
    const fake = fakeTransport({});
    const scores = createScores({ transport: fake.transport });

    expect((await scores.models()).ok).toBe(false);
    expect((await scores.saveModel({ key: "x" })).ok).toBe(false);
    expect((await scores.top("lead")).ok).toBe(false);
    expect(fake.calls).toEqual([]);
  });
});

describe("scoresSection", () => {
  it("loads a record's current scores", async () => {
    const fake = fakeTransport({ subject_scores: [SCORE] });
    const scores = createScores({ transport: fake.transport, tenant: "org-1" });

    const rows = await scoresSection
      .load(scores, { type: "lead", id: "l1" }, undefined)
      .orThrow();

    expect(rows).toHaveLength(1);
    expect(scoresBlock.sections).toEqual({ scores: scoresSection });
    expect(scoresSection.events).toEqual(["score.changed"]);
    expect(scoresEvents.types).toContain("score.changed");
  });
});
