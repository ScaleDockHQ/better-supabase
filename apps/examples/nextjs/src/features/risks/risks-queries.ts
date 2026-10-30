import "server-only";
import type { RiskStatus } from "better-supabase/blocks/risks";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

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

/** The tone a band's Badge takes, from its position in the matrix. */
export type BandTone = "low" | "medium" | "high" | "critical";

/** A risk as the register shows it, serializable. */
export interface RiskRow {
  readonly id: string;
  readonly number: string;
  readonly title: string;
  readonly category: string;
  readonly status: RiskStatus;
  /** The residual band's label, or null before the first assessment. */
  readonly band: string | null;
  readonly tone: BandTone | null;
  readonly score: number | null;
  readonly nextReviewOn: string | null;
}

/**
 * Maps the bands of a matrix onto the four tones by score: the lowest band is
 * `low`, the highest `critical`, the ones between `medium` and `high`.
 */
function tonesOf(
  bands: readonly { readonly key: string; readonly min: number }[],
): ReadonlyMap<string, BandTone> {
  const last = bands.length - 1;

  return new Map(
    bands
      .toSorted((a, b) => a.min - b.min)
      .map((band, index): readonly [string, BandTone] => {
        if (index === 0) {
          return [band.key, "low"];
        }

        if (index === last) {
          return [band.key, "critical"];
        }

        return [band.key, (index - 1) * 2 < last - 1 ? "medium" : "high"];
      }),
  );
}

async function loadRegister(): Promise<readonly RiskRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const [risks, matrices] = await Promise.all([
    db.risks.list({ limit: 200 }).orThrow(),
    db.risks.matrices().orThrow(),
  ]);

  const bands = new Map(
    matrices.map((matrix) => [
      matrix.id,
      {
        labels: new Map(matrix.bands.map((band) => [band.key, band.label])),
        tones: tonesOf(matrix.bands),
      },
    ]),
  );

  return risks.map((risk) => {
    const matrix = bands.get(risk.matrixId);
    const band = risk.residual?.band;

    return {
      id: risk.id,
      number: risk.number,
      title: risk.title,
      category: risk.category,
      status: risk.status,
      band: band === undefined ? null : (matrix?.labels.get(band) ?? band),
      tone: band === undefined ? null : (matrix?.tones.get(band) ?? null),
      score: risk.residual?.score ?? null,
      nextReviewOn: risk.nextReviewOn?.toString() ?? null,
    };
  });
}

/** The organization's risks, the highest residual score first. */
export function getRiskRegister(): Promise<Loaded<readonly RiskRow[]>> {
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
  readonly matrixName: string;
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

  const { matrix, cells } = await db.risks.heatmap().orThrow();
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
