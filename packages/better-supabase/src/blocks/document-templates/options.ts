import type { DocumentVariableType } from "../../sql/modules/document-templates-values.ts";
import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** One variable an app-defined document type offers to its templates. */
export type AppDocumentVariable = {
  /** A dotted path; a list item's field is `list[].field`. */
  readonly path: string;
  readonly type: DocumentVariableType;
  readonly description?: string;
};

/**
 * A document type the app defines. `variables` is its contract, and `function`
 * is the app's `schema.name(tenant, document_id)` that returns the variable
 * payload as jsonb, read through row level security like the built-in
 * builders.
 */
export type AppDocumentType = {
  readonly function: string;
  readonly variables: readonly AppDocumentVariable[];
};

/** `blocks.document-templates.options`. */
export type DocumentTemplatesSqlOptions = {
  /**
   * Document types of the app, keyed by name (lower case letters, digits and
   * `_`). They sit next to the built-in types: templates, text blocks,
   * snapshots, `render_document` and `freeze_document` take them.
   */
  readonly documentTypes?: Readonly<Record<string, AppDocumentType>>;
};

export const documentTemplatesSqlOptions: BlockOptionsSchema<DocumentTemplatesSqlOptions> =
  blockOptions<DocumentTemplatesSqlOptions>({
    documentTypes: option.unknown<Readonly<Record<string, AppDocumentType>>>(),
  });
