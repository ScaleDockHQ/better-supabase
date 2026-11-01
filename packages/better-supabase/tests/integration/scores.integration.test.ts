import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { FilterQuery } from "../../src/list/index.ts";
import type { TestUser } from "./block-session.ts";

import {
  createAutomationsAdmin,
  defineRuleFields,
} from "../../src/blocks/automations/index.ts";
import { createScores } from "../../src/blocks/scores/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const leads = defineRuleFields("lead", {
  stage: { type: "select", options: ["new", "qualified", "lost"] },
  revenue: { type: "number" },
  employees: { type: "number" },
  name: { type: "text" },
});

const is = (path: string, operator: string, value: unknown): FilterQuery => ({
  id: `g-${path}`,
  type: "group",
  combinator: "and",
  rules: [{ id: `r-${path}`, type: "rule", path: [path], operator, value }],
});

const LEAD = {
  key: "lead",
  name: "Lead score",
  subjectType: "lead",
  rules: [
    {
      id: "qualified",
      label: "Qualified",
      conditions: is("stage", "is", "qualified"),
      points: 20,
    },
    { id: "big", conditions: is("revenue", "gt", 100_000), points: 30 },
    { id: "lost", conditions: is("stage", "is", "lost"), points: -50 },
  ],
  metrics: [
    { id: "size", source: "field", field: "employees", weight: 0.5, cap: 25 },
    { id: "votes", source: "votes", weight: 2 },
  ],
  bands: [
    { label: "cold", min: -1000 },
    { label: "hot", min: 50 },
    { label: "warm", min: 20 },
  ],
} as const;

describe.skipIf(!live)("scores module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let outsider: TestUser;
  let tenant: string;

  const scoresFor = (organizationId: string) =>
    createScores({
      transport: sqlTransport(session.sql),
      tenant: organizationId,
    });

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install([
      "organizations",
      "outbox",
      "automations",
      "reactions",
      "scores",
    ]);
    owner = await session.user("scores-owner");
    member = await session.user("scores-member");
    outsider = await session.user("scores-outsider");
    tenant = await session.organization(owner, { member });
    await session.organization(outsider);
    await session.service();
    await createAutomationsAdmin({ transport: sqlTransport(session.sql) })
      .syncFields(leads)
      .orThrow();
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("saves versioned models and checks their rules and metrics", async () => {
    await session.as(owner);
    const scores = scoresFor(tenant);
    const model = await scores.saveModel(LEAD).orThrow();

    expect(model).toMatchObject({
      key: "lead",
      version: 1,
      enabled: true,
      bands: [
        { label: "hot", min: 50 },
        { label: "warm", min: 20 },
        { label: "cold", min: -1000 },
      ],
    });
    expect(model.rules[0]).toMatchObject({ label: "Qualified", points: 20 });
    expect(model.metrics[0]).toMatchObject({ field: "employees", cap: 25 });

    const same = await scores
      .saveModel({ id: model.id, name: "Lead score" })
      .orThrow();

    expect(same.version).toBe(1);

    const renamed = await scores
      .saveModel({ id: model.id, version: 1, description: "Inbound leads" })
      .orThrow();

    expect(renamed).toMatchObject({ version: 1, description: "Inbound leads" });

    const stale = await scores.saveModel({
      id: model.id,
      version: 9,
      name: "x",
    });

    expect(stale.error?.hint).toBe("SCORES_MODEL_CONFLICT");

    const bad = [
      { ...LEAD, key: "Bad Key" },
      { ...LEAD, key: "dup", subjectType: "nothing" },
      {
        ...LEAD,
        key: "dup",
        metrics: [{ id: "m", source: "field", field: "name" }],
      },
      { ...LEAD, key: "dup", metrics: [{ id: "m", source: "other" }] },
      { ...LEAD, key: "dup", bands: [{ label: "", min: 1 }] },
      { ...LEAD, key: "dup", rules: [{ id: "r", points: 1 }] },
    ] as const;

    const hints: (string | undefined)[] = [];

    for (const input of bad) {
      // SAFETY: invalid inputs on purpose, to reach the SQL checks.
      hints.push((await scores.saveModel(input as never)).error?.hint);
    }

    expect(hints).toEqual([
      "SCORES_MODEL_INVALID",
      "SCORES_SUBJECT_UNKNOWN",
      "SCORES_MODEL_INVALID",
      "SCORES_MODEL_INVALID",
      "SCORES_MODEL_INVALID",
      "SCORES_MODEL_INVALID",
    ]);
    expect((await scores.saveModel(LEAD)).error?.hint).toBe(
      "SCORES_MODEL_KEY_TAKEN",
    );
    expect(
      (await scores.saveModel({ id: model.id, subjectType: "party" })).error
        ?.hint,
    ).toBe("SCORES_MODEL_INVALID");

    const changed = await scores
      .saveModel({
        id: model.id,
        bands: [...LEAD.bands, { label: "lukewarm", min: 10 }],
      })
      .orThrow();

    expect(changed.version).toBe(2);

    const reverted = await scores
      .saveModel({ id: model.id, bands: LEAD.bands })
      .orThrow();

    expect(reverted.version).toBe(3);

    const detail = await scores.model(model.id).orThrow();
    expect(detail.versions.map((v) => v.version)).toEqual([3, 2, 1]);
    expect(await scores.models().orThrow()).toEqual([
      expect.objectContaining({ key: "lead" }),
    ]);
    expect(await scores.models({ subjectType: "party" }).orThrow()).toEqual([]);
  });

  it("computes scores, keeps history and emits score.changed", async () => {
    await session.service();
    await session.client.query(
      "insert into better_supabase.reaction_scores (tenant_id, subject_type, subject_id, score, up, down) values ($1, 'lead', 'l1', 3, 4, 1)",
      [tenant],
    );
    await session.as(owner);
    const scores = scoresFor(tenant);
    const lead = { type: "lead", id: "l1" };

    const first = await scores
      .compute({
        modelKey: "lead",
        subject: lead,
        fields: {
          stage: "qualified",
          revenue: 250_000,
          employees: 80,
          name: "Acme",
        },
      })
      .orThrow();

    expect(first).toMatchObject({
      changed: true,
      current: true,
      score: 81,
      band: "hot",
      modelKey: "lead",
      modelVersion: 3,
      subject: lead,
    });
    expect(first.breakdown).toEqual({
      rules: [
        { id: "qualified", label: "Qualified", matched: true, points: 20 },
        { id: "big", matched: true, points: 30 },
        { id: "lost", matched: false, points: 0 },
      ],
      metrics: [
        { id: "size", value: 80, points: 25 },
        { id: "votes", value: 3, points: 6 },
      ],
    });

    const again = await scores
      .compute({
        modelKey: "lead",
        subject: lead,
        fields: { stage: "qualified", revenue: 250_000, employees: 80 },
      })
      .orThrow();

    expect(again).toMatchObject({ changed: false, id: first.id });

    const lost = await scores
      .compute({
        modelKey: "lead",
        subject: lead,
        fields: { stage: "lost", revenue: null, employees: null },
      })
      .orThrow();

    expect(lost).toMatchObject({ changed: true, score: -44, band: "cold" });
    expect(lost.breakdown.metrics[0]).toEqual({
      id: "size",
      value: null,
      points: 0,
    });

    await scores
      .compute({
        modelKey: "lead",
        subject: { type: "lead", id: "l2" },
        fields: { stage: "new", employees: 30 },
      })
      .orThrow();

    expect(
      (await scores.history({ modelKey: "lead", subject: lead }).orThrow()).map(
        (s) => [s.score, s.current],
      ),
    ).toEqual([
      [-44, true],
      [81, false],
    ]);
    expect(await scores.list({ on: lead }).orThrow()).toEqual([
      expect.objectContaining({ score: -44, modelName: "Lead score" }),
    ]);
    expect(
      (await scores.top({ modelKey: "lead" }).orThrow()).map(
        (s) => s.subject.id,
      ),
    ).toEqual(["l2", "l1"]);
    expect(
      await scores.top({ modelKey: "lead", band: "hot" }).orThrow(),
    ).toEqual([]);
    expect(
      await scores
        .top({ modelKey: "lead", minScore: 0, pageSize: 1 })
        .orThrow(),
    ).toEqual([expect.objectContaining({ score: 15, band: "cold" })]);

    await session.service();

    const events = await session.rows<{ data: Record<string, unknown> }>(
      "select payload as data from better_supabase.outbox_events where organization_id = $1 and type = 'score.changed' order by position",
      [tenant],
    );

    expect(events.map((e) => e.data)).toEqual([
      expect.objectContaining({
        subjectId: "l1",
        score: 81,
        previousScore: null,
        band: "hot",
        previousBand: null,
      }),
      expect.objectContaining({
        subjectId: "l1",
        score: -44,
        previousScore: 81,
        band: "cold",
        previousBand: "hot",
      }),
      expect.objectContaining({ subjectId: "l2", score: 15 }),
    ]);
  });

  it("checks permissions, subjects and disabled models", async () => {
    await session.as(member);
    const scores = scoresFor(tenant);
    const lead = { type: "lead", id: "l1" };

    expect(
      (await scores.saveModel({ ...LEAD, key: "member" })).error?.hint,
    ).toBe("SCORES_FORBIDDEN");
    expect(
      (await scores.compute({ modelKey: "lead", subject: lead, fields: {} }))
        .error?.hint,
    ).toBe("SCORES_FORBIDDEN");
    expect(await scores.list({ on: lead }).orThrow()).toHaveLength(1);

    await session.as(outsider);
    expect((await scores.list({ on: lead })).error?.hint).toBe(
      "SCORES_FORBIDDEN",
    );
    expect((await scores.models()).error?.hint).toBe("SCORES_FORBIDDEN");
    expect(
      (await scores.history({ modelKey: "lead", subject: lead })).error?.hint,
    ).toBe("SCORES_FORBIDDEN");
    expect((await scores.top({ modelKey: "lead" })).error?.hint).toBe(
      "SCORES_FORBIDDEN",
    );

    await session.as(owner);
    const owned = scoresFor(tenant);
    const [model] = await owned.models().orThrow();

    expect(
      (await owned.compute({ modelKey: "missing", subject: lead, fields: {} }))
        .error?.hint,
    ).toBe("SCORES_MODEL_NOT_FOUND");
    expect(
      (
        await owned.compute({
          modelKey: "lead",
          subject: { type: "party", id: "p" },
          fields: {},
        })
      ).error?.hint,
    ).toBe("SCORES_SUBJECT_MISMATCH");

    await owned.saveModel({ id: model!.id, enabled: false }).orThrow();
    expect(
      (await owned.compute({ modelKey: "lead", subject: lead, fields: {} }))
        .error?.hint,
    ).toBe("SCORES_MODEL_DISABLED");

    await session.as(outsider);
    expect((await scoresFor(tenant).model(model!.id)).error?.kind).toBe(
      "not_found",
    );
    expect((await scoresFor(tenant).deleteModel(model!.id)).error?.hint).toBe(
      "SCORES_FORBIDDEN",
    );

    await session.as(owner);
    expect(await owned.deleteModel(model!.id).orThrow()).toBe(true);
    expect(await owned.deleteModel(model!.id).orThrow()).toBe(false);
    expect(
      await owned.history({ modelKey: "lead", subject: lead }).orThrow(),
    ).toEqual([]);
  });
});
