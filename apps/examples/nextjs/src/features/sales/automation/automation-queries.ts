import "server-only";
import { subjectKey } from "better-supabase/blocks/subjects";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { CRM_TAG } from "@/features/crm/crm-cache";
import { bsb } from "@/lib/supabase/server";

import { SALES_TAG } from "../sales-cache";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/**
 * The name of each subject through `subjects.label`; the id when none is
 * readable.
 */
async function namesOf(
  db: Db,
  type: string,
  ids: readonly string[],
): Promise<ReadonlyMap<string, string>> {
  const labels = await db.subjects
    .label(ids.map((id) => ({ type, id })))
    .orThrow();

  return new Map(
    ids.map((id) => [id, labels[subjectKey({ type, id })]?.label ?? id]),
  );
}

export interface SegmentRow {
  readonly id: string;
  readonly name: string;
  readonly description: string | null;
  readonly subjectType: string;
  readonly memberCount: number;
  /** ISO instant, `null` before the first refresh. */
  readonly refreshedAt: string | null;
  readonly rules: number;
}

function segmentOf(segment: {
  readonly id: string;
  readonly name: string;
  readonly description: string | undefined;
  readonly subjectType: string;
  readonly memberCount: number;
  readonly refreshedAt: { toString(): string } | undefined;
  readonly conditions: { readonly rules: readonly unknown[] };
}): SegmentRow {
  return {
    id: segment.id,
    name: segment.name,
    description: segment.description ?? null,
    subjectType: segment.subjectType,
    memberCount: segment.memberCount,
    refreshedAt: segment.refreshedAt?.toString() ?? null,
    rules: segment.conditions.rules.length,
  };
}

export async function loadSegments(): Promise<readonly SegmentRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const segments = await db.segments.list({ organizationId: tenant }).orThrow();

  return segments.map(segmentOf);
}

export interface SegmentDetail extends SegmentRow {
  readonly members: readonly {
    readonly subjectId: string;
    readonly name: string;
    readonly enteredAt: string;
  }[];
}

/** One segment with its newest 100 members. */
export async function loadSegment(
  id: string,
): Promise<SegmentDetail | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const segment = await db.segments.get(id).orThrow();

  if (!segment) {
    return undefined;
  }

  const members = await db.segments
    .members({ segmentId: id, limit: 100 })
    .orThrow();

  const names = await namesOf(
    db,
    segment.subjectType,
    members.map((member) => member.subjectId),
  );

  return {
    ...segmentOf(segment),
    members: members.map((member) => ({
      subjectId: member.subjectId,
      name: names.get(member.subjectId) ?? member.subjectId,
      enteredAt: member.enteredAt.toString(),
    })),
  };
}

export interface QueueRow {
  readonly id: string;
  readonly name: string;
  readonly subjectType: string;
  readonly strategy: string;
  readonly rank: number;
  readonly enabled: boolean;
  readonly members: number;
  readonly assigned: number;
}

export interface QueueMemberRow {
  readonly userId: string;
  readonly weight: number;
  readonly active: boolean;
  readonly assignedCount: number;
  readonly lastAssignedAt: string | null;
}

function queueOf(queue: {
  readonly id: string;
  readonly name: string;
  readonly subjectType: string;
  readonly strategy: string;
  readonly rank: number;
  readonly enabled: boolean;
  readonly members: readonly { readonly assignedCount: number }[];
}): QueueRow {
  return {
    id: queue.id,
    name: queue.name,
    subjectType: queue.subjectType,
    strategy: queue.strategy,
    rank: queue.rank,
    enabled: queue.enabled,
    members: queue.members.length,
    assigned: queue.members.reduce(
      (sum, member) => sum + member.assignedCount,
      0,
    ),
  };
}

export async function loadQueues(): Promise<readonly QueueRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const queues = await db.assignment
    .queues({ organizationId: tenant })
    .orThrow();

  return queues.map(queueOf);
}

export interface QueueDetail extends QueueRow {
  readonly memberRows: readonly QueueMemberRow[];
}

export async function loadQueue(
  id: string,
): Promise<QueueDetail | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const queues = await db.assignment
    .queues({ organizationId: tenant })
    .orThrow();

  const queue = queues.find((item) => item.id === id);

  if (!queue) {
    return undefined;
  }

  return {
    ...queueOf(queue),
    memberRows: queue.members.map((member) => ({
      userId: member.userId,
      weight: member.weight,
      active: member.active,
      assignedCount: member.assignedCount,
      lastAssignedAt: member.lastAssignedAt?.toString() ?? null,
    })),
  };
}

export interface ScoreModelRow {
  readonly id: string;
  readonly key: string;
  readonly name: string;
  readonly subjectType: string;
  readonly enabled: boolean;
  readonly version: number;
  readonly rules: number;
  readonly metrics: number;
  readonly bands: string;
}

export async function loadScoreModels(): Promise<
  readonly ScoreModelRow[] | null
> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const models = await db.scores.models().orThrow();

  return models.map((model) => ({
    id: model.id,
    key: model.key,
    name: model.name,
    subjectType: model.subjectType,
    enabled: model.enabled,
    version: model.version,
    rules: model.rules.length,
    metrics: model.metrics.length,
    bands: model.bands.map((band) => band.label).join(", "),
  }));
}

export interface ScoredRecord {
  readonly id: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly name: string;
  readonly score: number;
  readonly band: string | null;
  readonly computedAt: string;
  readonly matched: readonly string[];
}

export interface ScoreModelDetail {
  readonly model: ScoreModelRow & {
    readonly description: string | null;
    readonly ruleRows: readonly {
      readonly id: string;
      readonly label: string;
      readonly points: number;
    }[];
    readonly bandRows: readonly {
      readonly label: string;
      readonly min: number;
    }[];
    readonly versions: readonly {
      readonly version: number;
      readonly savedAt: string;
    }[];
  };
  /** The highest-scoring records under the model, newest computation. */
  readonly top: readonly ScoredRecord[];
}

/** One model with its rules, bands, versions and its 50 top-scored records. */
export async function loadScoreModel(
  id: string,
): Promise<ScoreModelDetail | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const model = await db.scores.model(id).orThrow();

  const top = await db.scores
    .top({ modelKey: model.key, pageSize: 50 })
    .orThrow();

  const names = await namesOf(
    db,
    model.subjectType,
    top.map((score) => score.subject.id),
  );

  return {
    model: {
      id: model.id,
      key: model.key,
      name: model.name,
      subjectType: model.subjectType,
      enabled: model.enabled,
      version: model.version,
      rules: model.rules.length,
      metrics: model.metrics.length,
      bands: model.bands.map((band) => band.label).join(", "),
      description: model.description ?? null,
      ruleRows: model.rules.map((rule) => ({
        id: rule.id,
        label: rule.label ?? rule.id,
        points: rule.points,
      })),
      bandRows: model.bands.map((band) => ({
        label: band.label,
        min: band.min,
      })),
      versions: model.versions.map((version) => ({
        version: version.version,
        savedAt: version.savedAt.toString(),
      })),
    },
    top: top.map((score) => ({
      id: score.id,
      subjectType: score.subject.type,
      subjectId: score.subject.id,
      name: names.get(score.subject.id) ?? score.subject.id,
      score: score.score,
      band: score.band ?? null,
      computedAt: score.computedAt.toString(),
      matched: score.breakdown.rules
        .filter((rule) => rule.matched)
        .map((rule) => rule.label ?? rule.id),
    })),
  };
}

export interface HealthRow {
  readonly id: string;
  readonly modelKey: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly name: string;
  readonly score: number;
  readonly band: string | null;
  readonly computedAt: string;
}

export interface HealthData {
  readonly models: readonly { readonly key: string; readonly name: string }[];
  readonly modelKey: string | null;
  readonly rows: readonly HealthRow[];
}

/**
 * Account health: the top 200 scores of one model, the one named `health` when
 * the organization has it and the first company model otherwise.
 */
export async function loadHealth(): Promise<HealthData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const models = await db.scores.models({ subjectType: "company" }).orThrow();
  const model = models.find((item) => item.key === "health") ?? models[0];

  if (!model) {
    return { models: [], modelKey: null, rows: [] };
  }

  const scores = await db.scores
    .top({ modelKey: model.key, pageSize: 200 })
    .orThrow();

  const nameOf = await namesOf(
    db,
    model.subjectType,
    scores.map((score) => score.subject.id),
  );

  return {
    models: models.map((item) => ({ key: item.key, name: item.name })),
    modelKey: model.key,
    rows: scores.map((score) => ({
      id: score.id,
      modelKey: score.modelKey,
      subjectType: score.subject.type,
      subjectId: score.subject.id,
      name: nameOf.get(score.subject.id) ?? score.subject.id,
      score: score.score,
      band: score.band ?? null,
      computedAt: score.computedAt.toString(),
    })),
  };
}

export interface ContactSales {
  readonly segments: readonly {
    readonly segmentId: string;
    readonly name: string;
    readonly enteredAt: string;
  }[];
  readonly scores: readonly {
    readonly id: string;
    readonly modelKey: string;
    readonly modelName: string | null;
    readonly score: number;
    readonly band: string | null;
    readonly computedAt: string;
    readonly matched: readonly string[];
  }[];
  readonly assignments: readonly {
    readonly queueId: string | null;
    readonly userId: string | null;
    readonly assignedAt: string;
  }[];
}

/** The segments a company or person is in, its scores and its queue history. */
export async function loadContactSales(
  type: "company" | "person",
  id: string,
): Promise<ContactSales | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [segments, scores, assignments] = await Promise.all([
    db.segments.of({ type, id }).orThrow(),
    db.scores.list({ on: { type, id } }).orThrow(),
    db.assignment
      .history({ organizationId: tenant, subject: { type, id }, limit: 10 })
      .orThrow(),
  ]);

  return {
    segments: segments.map((segment) => ({
      segmentId: segment.segmentId,
      name: segment.name,
      enteredAt: segment.enteredAt.toString(),
    })),
    scores: scores.map((score) => ({
      id: score.id,
      modelKey: score.modelKey,
      modelName: score.modelName ?? null,
      score: score.score,
      band: score.band ?? null,
      computedAt: score.computedAt.toString(),
      matched: score.breakdown.rules
        .filter((rule) => rule.matched)
        .map((rule) => rule.label ?? rule.id),
    })),
    assignments: assignments.map((entry) => ({
      queueId: entry.queueId ?? null,
      userId: entry.userId ?? null,
      assignedAt: entry.assignedAt.toString(),
    })),
  };
}

export interface FieldChangeRow {
  readonly id: string;
  readonly field: string;
  readonly before: string;
  readonly after: string;
  readonly changedBy: string | null;
  readonly changedAt: string;
}

// oxlint-disable-next-line anti-slop/no-unknown-parameters -- tracked column values are untyped JSON; they are only shown.
const show = (value: unknown): string =>
  value === null || value === undefined
    ? "–"
    : // oxlint-disable-next-line anti-slop/no-runtime-typeof -- a string shows as itself, any other JSON as its text.
      typeof value === "string"
      ? value
      : JSON.stringify(value);

/** The latest 50 tracked column changes of a company or a deal. */
export async function loadFieldHistory(
  type: "company" | "deal",
  id: string,
): Promise<readonly FieldChangeRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const changes = await db.fieldHistory
    .of({ subject: { type, id }, limit: 50 })
    .orThrow();

  return changes.map((change) => ({
    id: change.id,
    field: change.field,
    before: show(change.before),
    after: show(change.after),
    changedBy: change.changedBy ?? null,
    changedAt: change.changedAt.toString(),
  }));
}
