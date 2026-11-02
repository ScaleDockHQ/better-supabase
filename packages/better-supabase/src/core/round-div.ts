/**
 * Divides two bigints and rounds half away from zero. The sign of the result
 * follows the signs of both operands, so a negative denominator rounds like a
 * negative numerator.
 */
export function roundDiv(numerator: bigint, denominator: bigint): bigint {
  const negative = numerator < 0n !== denominator < 0n;
  const n = numerator < 0n ? -numerator : numerator;
  const d = denominator < 0n ? -denominator : denominator;
  const rounded = (n * 2n + d) / (d * 2n);

  return negative ? -rounded : rounded;
}
