/**
 * Where a movement's stock sits: a bin, a lot (by id, or by code with an expiry
 * date to create it) and the serial numbers it moves.
 */
export interface StockDetail {
  readonly binId?: string;
  readonly lotId?: string;
  /**
   * A lot by code, created when it doesn't exist yet; `expiresOn` is
   * `YYYY-MM-DD`.
   */
  readonly lot?: { readonly code: string; readonly expiresOn?: string };
  /** One per unit, for a variant tracked by serial. */
  readonly serials?: readonly string[];
}

/** `detail` as the SQL functions take it. */
export function detailArg(
  detail: StockDetail | undefined,
): Record<string, unknown> | null {
  if (detail === undefined) {
    return null;
  }

  return {
    ...(detail.binId === undefined ? {} : { binId: detail.binId }),
    ...(detail.lotId === undefined ? {} : { lotId: detail.lotId }),
    ...(detail.lot === undefined ? {} : { lot: { ...detail.lot } }),
    ...(detail.serials === undefined ? {} : { serials: [...detail.serials] }),
  };
}
