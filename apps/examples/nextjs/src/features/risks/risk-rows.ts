import type { RiskStatus } from "better-supabase/blocks/risks";

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

interface MatrixBands {
  readonly bands: readonly {
    readonly key: string;
    readonly label: string;
    readonly min: number;
  }[];
}

/**
 * Maps the bands of a matrix onto the four tones by score: the lowest band is
 * `low`, the highest `critical`, the ones between `medium` and `high`.
 */
export function tonesOf(
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

interface RiskLike {
  readonly id: string;
  readonly number: string;
  readonly title: string;
  readonly category: string;
  readonly status: RiskStatus;
  readonly matrixId: string;
  readonly residual?: { readonly band: string; readonly score: number };
  readonly nextReviewOn?: { toString(): string };
}

/** The register rows of a page of risks, with each band named by its matrix. */
export function toRiskRows(
  risks: readonly RiskLike[],
  matrices: readonly (MatrixBands & { readonly id: string })[],
): RiskRow[] {
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
