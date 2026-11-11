import "server-only";
import type { RiskPageOptions, RiskStatus } from "better-supabase/blocks/risks";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";
import * as v from "valibot";

import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";

import { bsb } from "@/lib/supabase/server";

import type { BandTone, RiskRow } from "./risk-rows";

import { riskList } from "./risk-list";
import { tonesOf, toRiskRows } from "./risk-rows";

export type { BandTone, RiskRow };

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
async function settle<T>(load: () => Promise<T | null>): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

const PAGE_SIZE = 50;

type PageDraft = { -readonly [K in keyof RiskPageOptions]: RiskPageOptions[K] };

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

const STATUSES: readonly string[] = [
  "identified",
  "assessed",
  "treating",
  "accepted",
  "closed",
] satisfies readonly RiskStatus[];

function isRiskStatus(value: string | undefined): value is RiskStatus {
  return value !== undefined && STATUSES.includes(value);
}

/** The first value of a facet: the block's page filters take one per key. */
function one(values: readonly string[] | undefined): string | undefined {
  return values?.[0];
}

/**
 * One keyset page of risks for a list query, with the matrices that name the
 * bands. The cursor travels in the URL as JSON.
 */
export async function readRiskPage(
  db: Db,
  query: RecordListUrlQuery,
): Promise<RecordListPage<RiskRow>> {
  const status = one(query.facets["status"]);

  const options: PageDraft = { limit: PAGE_SIZE };

  const category = one(query.facets["category"]);
  const band = one(query.facets["band"]);
  const after = query.after === undefined ? undefined : cursorOf(query.after);

  if (query.q !== undefined) {
    options.search = query.q;
  }

  if (isRiskStatus(status)) {
    options.status = status;
  }

  if (category !== undefined) {
    options.category = category;
  }

  if (band !== undefined) {
    options.band = band;
  }

  if (after !== undefined) {
    options.after = after;
  }

  const [page, matrices] = await Promise.all([
    db.risks.page(options).orThrow(),
    db.risks.matrices().orThrow(),
  ]);

  return {
    items: toRiskRows(page.items, matrices),
    nextCursor:
      page.nextCursor === null ? null : JSON.stringify(page.nextCursor),
  };
}

const cursorSchema = v.array(v.string());

function cursorOf(value: string): readonly string[] | undefined {
  try {
    const parsed = v.safeParse(cursorSchema, JSON.parse(value));

    return parsed.success ? parsed.output : undefined;
  } catch {
    return undefined;
  }
}

async function loadRegister(): Promise<RecordListPage<RiskRow> | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  return readRiskPage(db, riskList.defaults);
}

/**
 * The first page of the organization's risks, the highest residual score first.
 * Filtered and later pages go through `/api/risks/list`.
 */
export function getRiskRegister(): Promise<Loaded<RecordListPage<RiskRow>>> {
  return settle(loadRegister);
}

/** One heatmap cell, serializable. */
export interface HeatmapCell {
  readonly likelihood: number;
  readonly impact: number;
  readonly band: string;
  readonly tone: BandTone;
  readonly count: number;
}

export interface HeatmapData {
  /** The default matrix's name, or null while the organization has none. */
  readonly matrixName: string | null;
  /** Labels by level, lowest first. */
  readonly likelihoods: readonly {
    readonly level: number;
    readonly label: string;
  }[];
  readonly impacts: readonly {
    readonly level: number;
    readonly label: string;
  }[];
  readonly cells: readonly HeatmapCell[];
  readonly total: number;
}

async function loadHeatmap(): Promise<HeatmapData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const call = db.risks.heatmap();
  const heatmap = await call;

  if (!heatmap.ok && heatmap.error.hint === "RISK_MATRIX_NOT_FOUND") {
    return {
      matrixName: null,
      likelihoods: [],
      impacts: [],
      cells: [],
      total: 0,
    };
  }

  const { matrix, cells } = heatmap.ok ? heatmap.data : await call.orThrow();
  const tones = tonesOf(matrix.bands);
  const labels = new Map(matrix.bands.map((band) => [band.key, band.label]));

  return {
    matrixName: matrix.name,
    likelihoods: matrix.likelihoodLevels
      .map(({ value, label }) => ({ level: value, label }))
      .toSorted((a, b) => a.level - b.level),
    impacts: matrix.impactLevels
      .map(({ value, label }) => ({ level: value, label }))
      .toSorted((a, b) => a.level - b.level),
    cells: cells.map((cell) => ({
      likelihood: cell.likelihood,
      impact: cell.impact,
      band: labels.get(cell.band) ?? cell.band,
      tone: tones.get(cell.band) ?? "medium",
      count: cell.count,
    })),
    total: cells.reduce((sum, cell) => sum + cell.count, 0),
  };
}

/** The open risks per cell of the default matrix, by residual rating. */
export function getRiskHeatmap(): Promise<Loaded<HeatmapData>> {
  return settle(loadHeatmap);
}

/** One rating, as the detail page shows it. */
export interface RiskRatingView {
  readonly likelihood: number;
  readonly impact: number;
  readonly score: number;
  readonly band: string;
  readonly tone: BandTone | null;
}

/** A risk with its matrix names, assessments and links, serializable. */
export interface RiskDetailData {
  readonly row: RiskRow;
  readonly description: string | null;
  readonly cause: string | null;
  readonly consequence: string | null;
  readonly treatment: string | null;
  readonly reviewIntervalMonths: number | null;
  readonly matrixName: string;
  readonly inherent: RiskRatingView | null;
  readonly residual: RiskRatingView | null;
  readonly assessments: readonly {
    readonly id: string;
    readonly assessedAt: string;
    readonly rationale: string | null;
    readonly inherent: RiskRatingView;
    readonly residual: RiskRatingView;
  }[];
  readonly barriers: readonly RiskLinkView[];
  readonly cases: readonly RiskLinkView[];
}

export interface RiskLinkView {
  readonly linkId: string;
  readonly type: string;
  readonly id: string;
  readonly title: string | null;
}

async function loadRisk(id: string): Promise<RiskDetailData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const call = db.risks.get(id);
  const found = await call;

  if (!found.ok && found.error.hint === "RISK_NOT_FOUND") {
    return null;
  }

  const risk = found.ok ? found.data : await call.orThrow();

  const labels = new Map(
    risk.matrix.bands.map((band) => [band.key, band.label]),
  );

  const tones = tonesOf(risk.matrix.bands);

  const view = (rating: {
    readonly likelihood: number;
    readonly impact: number;
    readonly score: number;
    readonly band: string;
  }): RiskRatingView => ({
    likelihood: rating.likelihood,
    impact: rating.impact,
    score: rating.score,
    band: labels.get(rating.band) ?? rating.band,
    tone: tones.get(rating.band) ?? null,
  });

  const [row] = toRiskRows([risk], [risk.matrix]);

  if (row === undefined) {
    return null;
  }

  const link = (item: {
    readonly linkId: string;
    readonly type: string;
    readonly id: string;
    readonly title?: string;
  }): RiskLinkView => ({
    linkId: item.linkId,
    type: item.type,
    id: item.id,
    title: item.title ?? null,
  });

  return {
    row,
    description: risk.description ?? null,
    cause: risk.cause ?? null,
    consequence: risk.consequence ?? null,
    treatment: risk.treatment ?? null,
    reviewIntervalMonths: risk.reviewIntervalMonths ?? null,
    matrixName: risk.matrix.name,
    inherent: risk.inherent ? view(risk.inherent) : null,
    residual: risk.residual ? view(risk.residual) : null,
    assessments: risk.assessments.map((assessment) => ({
      id: assessment.id,
      assessedAt: assessment.assessedAt.toString(),
      rationale: assessment.rationale ?? null,
      inherent: view(assessment.inherent),
      residual: view(assessment.residual),
    })),
    barriers: risk.barriers.map(link),
    cases: risk.cases.map(link),
  };
}

/** One risk with its assessments and links; `null` when it is gone or hidden. */
export function getRisk(id: string): Promise<Loaded<RiskDetailData>> {
  return settle(() => loadRisk(id));
}
