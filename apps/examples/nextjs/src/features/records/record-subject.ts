/**
 * The record types whose pages show the shared sections (files, related
 * records, timeline). A page for another type adds its name here and its links
 * in `records-queries.ts`.
 */
export const RECORD_TYPES = ["customer", "company", "person", "deal"] as const;

export type RecordType = (typeof RECORD_TYPES)[number];

/** The record a section belongs to. */
export interface RecordSubject {
  readonly type: RecordType;
  readonly id: string;
}
