/** A visible range, as a date picker, schedule or event calendar reports it. */
export interface VisibleRange {
  readonly start: Date;
  readonly end: Date;
}

/** Whether two ranges cover the same instants. */
export function sameRange(a: VisibleRange, b: VisibleRange): boolean {
  return (
    a.start.getTime() === b.start.getTime() &&
    a.end.getTime() === b.end.getTime()
  );
}
