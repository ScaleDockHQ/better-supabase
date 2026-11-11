/** One row of the customers overview, as the page and the list route send it. */
export interface CustomerRow {
  readonly id: string;
  readonly name: string;
  readonly status: string;
  readonly logoUrl: string | null;
  readonly notes: number;
  readonly lastNoteAt: string | null;
}
