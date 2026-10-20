/**
 * The data of an app table event (ADR 0048): `<type>.created`, `.updated`
 * and `.deleted`, written by the trigger `appTables.<table>.events` adds.
 */
export interface AppTableEventData {
  /** The row id. */
  readonly id: string | number;
  /** The row's tenant, for tables kept per tenant. */
  readonly organizationId?: string;
  /** Set when the table registers a subject. */
  readonly subjectType?: string;
  readonly subjectId?: string;
  /** The columns an update changed, `updated_at` left out. */
  readonly changed?: readonly string[];
  /** The values of the columns in `events.include`. */
  readonly [column: string]: unknown;
}
