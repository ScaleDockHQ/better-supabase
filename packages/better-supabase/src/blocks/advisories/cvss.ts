import type { Result } from "../../core/result.ts";

import { dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";

/** The qualitative rating of a CVSS score (CVSS 3.1 section 5). */
export type CvssSeverity = "none" | "low" | "medium" | "high" | "critical";

/** A parsed CVSS vector string. */
export interface CvssScore {
  /** `3.0`, `3.1` or `4.0`. */
  readonly version: "3.0" | "3.1" | "4.0";
  /** The vector, as given, without surrounding whitespace. */
  readonly vector: string;
  /** Every metric in the vector, such as `{ AV: "N", AC: "L" }`. */
  readonly metrics: Readonly<Record<string, string>>;
  /**
   * The base score of a 3.x vector. A 4.0 vector is validated and parsed but
   * not scored: its score comes from a lookup over macro vectors that the block
   * does not carry, so take it from the source that published it.
   */
  readonly baseScore: number | undefined;
  /** The rating of `baseScore`; `undefined` when there is no score. */
  readonly severity: CvssSeverity | undefined;
}

const V3_BASE: Readonly<Record<string, readonly string[]>> = {
  AV: ["N", "A", "L", "P"],
  AC: ["L", "H"],
  PR: ["N", "L", "H"],
  UI: ["N", "R"],
  S: ["U", "C"],
  C: ["H", "L", "N"],
  I: ["H", "L", "N"],
  A: ["H", "L", "N"],
};

/** Temporal and environmental metrics of 3.x, validated by key only. */
const V3_OPTIONAL = new Set([
  "E",
  "RL",
  "RC",
  "CR",
  "IR",
  "AR",
  "MAV",
  "MAC",
  "MPR",
  "MUI",
  "MS",
  "MC",
  "MI",
  "MA",
]);

const V4_BASE: Readonly<Record<string, readonly string[]>> = {
  AV: ["N", "A", "L", "P"],
  AC: ["L", "H"],
  AT: ["N", "P"],
  PR: ["N", "L", "H"],
  UI: ["N", "P", "A"],
  VC: ["H", "L", "N"],
  VI: ["H", "L", "N"],
  VA: ["H", "L", "N"],
  SC: ["H", "L", "N"],
  SI: ["H", "L", "N"],
  SA: ["H", "L", "N"],
};

/** Threat, environmental, supplemental metrics of 4.0, validated by key only. */
const V4_OPTIONAL = new Set([
  "E",
  "CR",
  "IR",
  "AR",
  "MAV",
  "MAC",
  "MAT",
  "MPR",
  "MUI",
  "MVC",
  "MVI",
  "MVA",
  "MSC",
  "MSI",
  "MSA",
  "S",
  "AU",
  "R",
  "V",
  "RE",
  "U",
]);

const AV_WEIGHT: Readonly<Record<string, number>> = {
  N: 0.85,
  A: 0.62,
  L: 0.55,
  P: 0.2,
};

const AC_WEIGHT: Readonly<Record<string, number>> = { L: 0.77, H: 0.44 };
const UI_WEIGHT: Readonly<Record<string, number>> = { N: 0.85, R: 0.62 };
const CIA_WEIGHT: Readonly<Record<string, number>> = { H: 0.56, L: 0.22, N: 0 };

const PR_WEIGHT: Readonly<
  Record<"unchanged" | "changed", Readonly<Record<string, number>>>
> = {
  unchanged: { N: 0.85, L: 0.62, H: 0.27 },
  changed: { N: 0.85, L: 0.68, H: 0.5 },
};

/**
 * The smallest number with one decimal that is at least `value` (3.1 Appendix
 * A).
 */
function roundUp31(value: number): number {
  const integer = Math.round(value * 100_000);

  return integer % 10_000 === 0
    ? integer / 100_000
    : (Math.floor(integer / 10_000) + 1) / 10;
}

/** The 3.0 round up: the smallest one-decimal number at least `value`. */
const roundUp30 = (value: number): number => Math.ceil(value * 10) / 10;

/** The qualitative rating of a score from 0.0 to 10.0. */
export function cvssSeverity(score: number): CvssSeverity {
  if (score === 0) {
    return "none";
  }

  if (score < 4) {
    return "low";
  }

  if (score < 7) {
    return "medium";
  }

  return score < 9 ? "high" : "critical";
}

function invalid(message: string): Result<never> {
  return err(
    dbError("validation", message, { issues: [{ message, path: ["vector"] }] }),
  );
}

/** Reads `KEY:VALUE` pairs after the prefix, refusing repeats and bad pairs. */
function metricsOf(
  parts: readonly string[],
): Result<Readonly<Record<string, string>>> {
  const metrics: Record<string, string> = {};

  for (const part of parts) {
    const [key, value, ...rest] = part.split(":");

    if (
      key === undefined ||
      value === undefined ||
      rest.length > 0 ||
      !/^[A-Za-z]{1,3}$/u.test(key) ||
      !/^[A-Za-z0-9]{1,3}$/u.test(value)
    ) {
      return invalid(`"${part}" is not a CVSS metric`);
    }

    if (key in metrics) {
      return invalid(`metric ${key} appears twice`);
    }

    metrics[key] = value;
  }

  return ok(metrics);
}

function checkMetrics(
  metrics: Readonly<Record<string, string>>,
  base: Readonly<Record<string, readonly string[]>>,
  optional: ReadonlySet<string>,
): Result<void> {
  for (const [key, values] of Object.entries(base)) {
    const value = metrics[key];

    if (value === undefined) {
      return invalid(`base metric ${key} is missing`);
    }

    if (!values.includes(value)) {
      return invalid(`${value} is not a value of metric ${key}`);
    }
  }

  for (const key of Object.keys(metrics)) {
    if (!(key in base) && !optional.has(key)) {
      return invalid(`${key} is not a CVSS metric`);
    }
  }

  return ok(undefined);
}

function baseScoreV3(
  metrics: Readonly<Record<string, string>>,
  roundUp: (value: number) => number,
): number {
  const metric = (key: string): string => metrics[key] ?? "";
  const changed = metric("S") === "C";

  const iss =
    1 -
    (1 - (CIA_WEIGHT[metric("C")] ?? 0)) *
      (1 - (CIA_WEIGHT[metric("I")] ?? 0)) *
      (1 - (CIA_WEIGHT[metric("A")] ?? 0));

  const impact = changed
    ? 7.52 * (iss - 0.029) - 3.25 * (iss - 0.02) ** 15
    : 6.42 * iss;

  const exploitability =
    8.22 *
    (AV_WEIGHT[metric("AV")] ?? 0) *
    (AC_WEIGHT[metric("AC")] ?? 0) *
    (PR_WEIGHT[changed ? "changed" : "unchanged"][metric("PR")] ?? 0) *
    (UI_WEIGHT[metric("UI")] ?? 0);

  if (impact <= 0) {
    return 0;
  }

  return changed
    ? roundUp(Math.min(1.08 * (impact + exploitability), 10))
    : roundUp(Math.min(impact + exploitability, 10));
}

/**
 * Parses a CVSS 3.0, 3.1 or 4.0 vector string, such as
 * `CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H`. Every base metric must be
 * there with a value its version allows, and temporal and environmental metrics
 * are accepted by name. A 3.x vector gets its base score and rating; a 4.0
 * vector does not (see `CvssScore.baseScore`). A bad vector is a `validation`
 * error.
 */
export function parseCvss(input: string): Result<CvssScore> {
  const vector = input.trim();
  const [prefix, ...parts] = vector.split("/");
  const version = /^CVSS:(3\.0|3\.1|4\.0)$/u.exec(prefix ?? "")?.[1];

  if (version !== "3.0" && version !== "3.1" && version !== "4.0") {
    return invalid("a CVSS vector starts with CVSS:3.0, CVSS:3.1 or CVSS:4.0");
  }

  const metrics = metricsOf(parts);

  if (!metrics.ok) {
    return metrics;
  }

  const checked =
    version === "4.0"
      ? checkMetrics(metrics.data, V4_BASE, V4_OPTIONAL)
      : checkMetrics(metrics.data, V3_BASE, V3_OPTIONAL);

  if (!checked.ok) {
    return checked;
  }

  if (version === "4.0") {
    return ok({
      version,
      vector,
      metrics: metrics.data,
      baseScore: undefined,
      severity: undefined,
    });
  }

  const baseScore = baseScoreV3(
    metrics.data,
    version === "3.1" ? roundUp31 : roundUp30,
  );

  return ok({
    version,
    vector,
    metrics: metrics.data,
    baseScore,
    severity: cvssSeverity(baseScore),
  });
}
