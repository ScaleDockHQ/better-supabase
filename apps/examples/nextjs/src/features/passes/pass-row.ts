/** One row of the pass overview, as the page and the list route send it. */
export interface PassRow {
  readonly id: string;
  readonly kind: string;
  readonly holder: string | null;
  readonly status: "active" | "revoked";
  readonly uses: number;
  readonly usesAllowed: number | null;
  readonly validFrom: string;
  readonly validUntil: string | null;
  readonly createdAt: string;
}
