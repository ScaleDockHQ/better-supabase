import { isRecord, recordOf, textOf, toInstant } from "../shared.ts";

/** One field a document type declares for its files' metadata. */
export interface DocumentField {
  readonly type:
    | "text"
    | "number"
    | "amount"
    | "date"
    | "expiry"
    | "boolean"
    | "select";
  readonly required?: boolean;
  /** The allowed values of a `select` field. */
  readonly options?: readonly string[];
}

/** A kind of document an organization files, with the metadata it carries. */
export interface DocumentType {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  readonly fields: Readonly<Record<string, DocumentField>>;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** An `attachment_document_types` row. */
export function documentTypeOf(value: unknown): DocumentType {
  const row = recordOf(value, "attachment_document_types");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    // SAFETY: the database validates `fields` against the document field schema.
    fields: isRecord(row["fields"])
      ? (row["fields"] as Readonly<Record<string, DocumentField>>)
      : {},
    createdAt: toInstant(textOf(row["created_at"])),
    updatedAt: toInstant(textOf(row["updated_at"])),
  };
}
