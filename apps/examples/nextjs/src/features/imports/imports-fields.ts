/** The customer columns a CSV column can map to. `name` is required. */
export const CUSTOMER_IMPORT_FIELDS = ["name", "status", "kvk"] as const;

export type CustomerImportField = (typeof CUSTOMER_IMPORT_FIELDS)[number];

/** CSV header to customer column, without the skipped columns. */
export type ColumnMapping = Readonly<Record<string, CustomerImportField>>;
