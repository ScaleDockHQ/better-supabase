/**
 * The committed number stays while the measurement is inside the slack. A new
 * entry, a rise past the slack, or a drop past the slack takes the measurement.
 * Anything closer keeps the number already in the file, so two pull requests do
 * not both rewrite it.
 */
export function keptMeasurement(
  before: number | undefined,
  now: number,
  room: (before: number) => number,
): number {
  if (before === undefined) {
    return now;
  }

  const slack = room(before);

  if (now > before + slack || now < before - slack) {
    return now;
  }

  return before;
}
