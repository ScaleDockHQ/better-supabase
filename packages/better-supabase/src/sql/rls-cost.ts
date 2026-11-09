/**
 * True when a measured plan cost is more than `tolerance` above the baseline.
 * The nightly RLS check fails a generated policy that gets that much more
 * expensive for the same ten organizations.
 */
export function planCostRegressed(
  baseline: number,
  actual: number,
  tolerance = 0.2,
): boolean {
  if (!(baseline > 0) || !(actual >= 0) || !(tolerance >= 0)) {
    throw new TypeError(
      "plan cost needs a positive baseline, a measured cost and a tolerance",
    );
  }

  return actual > baseline * (1 + tolerance);
}
