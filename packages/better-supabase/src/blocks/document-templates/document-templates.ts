import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type {
  DocumentType,
  DocumentTemplateIssueCode,
} from "../../sql/modules/document-templates-values.ts";
import type { BlockOptions } from "../shared.ts";
import type { DocumentTemplateIssue } from "./template.ts";
import type { DocumentVariables } from "./variables.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { err } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  isRecord,
  nullableInstant,
  nullableText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { renderDocumentHtml } from "./template.ts";

/** A template of one slot: a document type, a name, an entity and a language. */
export interface DocumentTemplate {
  readonly id: string;
  readonly organizationId: string;
  /** The legal entity it belongs to; null for the organization. */
  readonly legalEntityId: string | null;
  readonly documentType: DocumentType;
  /** A code such as `nl`; null for any language. */
  readonly language: string | null;
  readonly name: string;
  /** The template body: HTML with placeholders. */
  readonly body: string;
  /** Raised by one each time the body changes. */
  readonly version: number;
  readonly active: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** A reusable text a template reads as `texts.<key>`. */
export interface DocumentTextBlock {
  readonly id: string;
  readonly organizationId: string;
  readonly legalEntityId: string | null;
  readonly key: string;
  readonly language: string | null;
  readonly body: string;
  readonly version: number;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** Where a chosen template came from in the fallback chain. */
export type DocumentTemplateSource =
  | "entity_language"
  | "entity"
  | "organization_language"
  | "organization"
  | "entity_other_language"
  | "organization_other_language";

/** The template `resolveTemplate` and `render` choose. */
export interface ResolvedDocumentTemplate {
  readonly id: string;
  readonly name: string;
  readonly documentType: DocumentType;
  readonly legalEntityId: string | null;
  readonly language: string | null;
  readonly version: number;
  readonly body: string;
  readonly source: DocumentTemplateSource;
}

/** One document as a renderer needs it. */
export interface RenderedDocument {
  readonly contractVersion: number;
  readonly documentType: DocumentType;
  readonly documentId: string;
  /** The legal entity that issues the document; null when there is none. */
  readonly legalEntityId: string | null;
  /** The language the template and blocks were chosen for. */
  readonly language: string | null;
  readonly variables: DocumentVariables;
  /** Null when no template fits; the document still has its variables. */
  readonly template: ResolvedDocumentTemplate | null;
  /** The text blocks the template reads, by key. */
  readonly blocks: Readonly<Record<string, string>>;
  /** Whether this is the copy frozen when the document was issued. */
  readonly frozen: boolean;
  readonly frozenAt: Temporal.Instant | null;
  readonly snapshotId: string | null;
}

export interface SaveDocumentTemplateInput {
  readonly documentType: DocumentType;
  readonly body: string;
  /** Default `default`; a document type can hold several named templates. */
  readonly name?: string;
  readonly language?: string | null;
  readonly legalEntityId?: string | null;
  /** Default true. */
  readonly active?: boolean;
}

export interface SaveDocumentTextBlockInput {
  readonly key: string;
  readonly body: string;
  readonly language?: string | null;
  readonly legalEntityId?: string | null;
}

export interface RenderDocumentInput {
  readonly documentType: DocumentType;
  readonly documentId: string;
  /** Overrides the buyer's language. */
  readonly language?: string;
  /** Render with today's templates even when the document was frozen. */
  readonly fresh?: boolean;
  /** The template name; default `default`. */
  readonly templateName?: string;
}

export interface FreezeDocumentInput {
  readonly documentType: DocumentType;
  readonly documentId: string;
  readonly language?: string;
  readonly templateName?: string;
}

/** What the SQL contract function returns for one document type. */
export interface DocumentContractSummary {
  readonly version: number;
  readonly documentType: DocumentType;
  readonly variables: readonly {
    readonly path: string;
    readonly type: string;
  }[];
}

export interface DocumentTemplatesOptions extends BlockOptions {
  readonly hooks?: NoInfer<BlockHooks<DocumentTemplates>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/**
 * Document templates: per legal entity and language templates for invoices,
 * credit notes, quotes, orders, dunning letters, delivery notes and statements,
 * reusable text blocks and `render`, which returns the variables of a document
 * with its chosen template. Reads need `document_templates.read` and writes
 * `document_templates.manage`.
 */
export interface DocumentTemplates {
  /**
   * Saves the template of a slot. A changed body raises the version. An unknown
   * variable fails with the hint `DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE`, an
   * unclosed block with `DOCUMENT_TEMPLATE_SYNTAX`.
   */
  saveTemplate(input: SaveDocumentTemplateInput): AsyncResult<DocumentTemplate>;
  /** An inactive template leaves the fallback chain. */
  setTemplateActive(id: string, active: boolean): AsyncResult<DocumentTemplate>;
  getTemplate(id: string): AsyncResult<DocumentTemplate>;
  listTemplates(filter?: {
    readonly documentType?: DocumentType;
    readonly legalEntityId?: string;
    readonly activeOnly?: boolean;
  }): AsyncResult<readonly DocumentTemplate[]>;
  saveTextBlock(
    input: SaveDocumentTextBlockInput,
  ): AsyncResult<DocumentTextBlock>;
  listTextBlocks(filter?: {
    readonly key?: string;
    readonly legalEntityId?: string;
  }): AsyncResult<readonly DocumentTextBlock[]>;
  /**
   * The template a document of this entity and language gets: the entity's in
   * the language, the entity's for any language, the organization's in the
   * language, then the organization's for any language. `undefined` when none
   * fits.
   */
  resolveTemplate(input: {
    readonly documentType: DocumentType;
    readonly legalEntityId?: string;
    readonly language?: string;
    readonly name?: string;
  }): AsyncResult<ResolvedDocumentTemplate | undefined>;
  /** The variables, template and text blocks of one document. */
  render(input: RenderDocumentInput): AsyncResult<RenderedDocument>;
  /**
   * `render`, then the HTML of the chosen template. Fails with the hint
   * `DOCUMENT_TEMPLATE_MISSING` when no template fits.
   */
  renderHtml(input: RenderDocumentInput): AsyncResult<string>;
  /**
   * Freezes a document so `render` returns the same variables, template and
   * blocks from now on. An issued invoice or credit note freezes itself.
   */
  freeze(input: FreezeDocumentInput): AsyncResult<RenderedDocument>;
  /** The version and the variable paths of one document type. */
  contract(documentType: DocumentType): AsyncResult<DocumentContractSummary>;
  /** The problems of a body, from the database's validator; empty when valid. */
  validate(input: {
    readonly documentType: DocumentType;
    readonly body: string;
    /** Validate as a text block, which may read any document type. */
    readonly textBlock?: boolean;
  }): AsyncResult<readonly DocumentTemplateIssue[]>;
}

function documentTypeOf(value: unknown): DocumentType {
  const text = textOf(value);

  switch (text) {
    case "invoice":
    case "credit_note":
    case "quote":
    case "order":
    case "dunning_letter":
    case "delivery_note":
    case "statement": {
      return text;
    }

    default: {
      throw new TypeError(`unknown document type ${text}`);
    }
  }
}

function templateOf(value: unknown, fn: string): DocumentTemplate {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    legalEntityId: nullableText(row["legalEntityId"]),
    documentType: documentTypeOf(row["documentType"]),
    language: nullableText(row["language"]),
    name: textOf(row["name"]),
    body: textOf(row["body"]),
    version: Number(row["version"]),
    active: row["active"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

function blockOf(value: unknown, fn: string): DocumentTextBlock {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    legalEntityId: nullableText(row["legalEntityId"]),
    key: textOf(row["key"]),
    language: nullableText(row["language"]),
    body: textOf(row["body"]),
    version: Number(row["version"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

function sourceOf(value: unknown): DocumentTemplateSource {
  switch (value) {
    case "entity_language":
    case "entity":
    case "organization_language":
    case "organization":
    case "entity_other_language": {
      return value;
    }

    default: {
      return "organization_other_language";
    }
  }
}

function resolvedOf(
  value: unknown,
  fn: string,
): ResolvedDocumentTemplate | null {
  if (value === null || value === undefined) {
    return null;
  }

  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    name: textOf(row["name"]),
    documentType: documentTypeOf(row["documentType"]),
    legalEntityId: nullableText(row["legalEntityId"]),
    language: nullableText(row["language"]),
    version: Number(row["version"]),
    body: textOf(row["body"]),
    source: sourceOf(row["source"]),
  };
}

function isDocumentVariables(value: unknown): value is DocumentVariables {
  return (
    isRecord(value) &&
    isRecord(value["document"]) &&
    isRecord(value["entity"]) &&
    isRecord(value["buyer"]) &&
    Array.isArray(value["lines"]) &&
    Array.isArray(value["tax_lines"]) &&
    isRecord(value["totals"]) &&
    isRecord(value["payment_terms"])
  );
}

function renderedOf(value: unknown, fn: string): RenderedDocument {
  const row = recordOf(value, fn);
  const variables = row["variables"];

  if (!isDocumentVariables(variables)) {
    throw new TypeError(`${fn} returned variables without the contract keys`);
  }

  const blocks: Record<string, string> = {};

  if (isRecord(row["blocks"])) {
    for (const [key, body] of Object.entries(row["blocks"])) {
      blocks[key] = textOf(body);
    }
  }

  return {
    contractVersion: Number(row["contractVersion"]),
    documentType: documentTypeOf(row["documentType"]),
    documentId: textOf(row["documentId"]),
    legalEntityId: nullableText(row["legalEntityId"]),
    language: nullableText(row["language"]),
    variables,
    template: resolvedOf(row["template"], fn),
    blocks,
    frozen: row["frozen"] === true,
    frozenAt: nullableInstant(row["frozenAt"]),
    snapshotId: nullableText(row["snapshotId"]),
  };
}

function issueCodeOf(value: unknown): DocumentTemplateIssueCode {
  switch (value) {
    case "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE":
    case "DOCUMENT_TEMPLATE_UNKNOWN_FILTER": {
      return value;
    }

    default: {
      return "DOCUMENT_TEMPLATE_SYNTAX";
    }
  }
}

export function createDocumentTemplates(
  options: DocumentTemplatesOptions,
): DocumentTemplates {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const one = (fn: string) => (value: unknown) => templateOf(value, fn);

  const renderArgs = (
    organizationId: string,
    input: RenderDocumentInput,
  ): Record<string, unknown> => ({
    tenant: organizationId,
    document_type: input.documentType,
    document_id: input.documentId,
    language: input.language ?? null,
    fresh: input.fresh ?? false,
    template_name: input.templateName ?? null,
  });

  const render = (input: RenderDocumentInput): AsyncResult<RenderedDocument> =>
    tenant().andThen((organizationId) =>
      call("render_document", renderArgs(organizationId, input), (value) =>
        renderedOf(value, "render_document"),
      ),
    );

  const client: DocumentTemplates = {
    saveTemplate: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_document_template",
          {
            tenant: organizationId,
            document_type: input.documentType,
            body: input.body,
            language: input.language ?? null,
            name: input.name ?? "default",
            legal_entity_id: input.legalEntityId ?? null,
            active: input.active ?? true,
          },
          one("save_document_template"),
        ),
      ),
    setTemplateActive: (id, active) =>
      call(
        "set_document_template_active",
        { template_id: id, active },
        one("set_document_template_active"),
      ),
    getTemplate: (id) =>
      call(
        "get_document_template",
        { template_id: id },
        one("get_document_template"),
      ),
    listTemplates: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_document_templates",
          {
            tenant: organizationId,
            document_type: filter.documentType ?? null,
            legal_entity_id: filter.legalEntityId ?? null,
            active_only: filter.activeOnly ?? false,
          },
          (value) =>
            recordsOf(value, "list_document_templates").map((row) =>
              templateOf(row, "list_document_templates"),
            ),
        ),
      ),
    saveTextBlock: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_document_text_block",
          {
            tenant: organizationId,
            key: input.key,
            body: input.body,
            language: input.language ?? null,
            legal_entity_id: input.legalEntityId ?? null,
          },
          (value) => blockOf(value, "save_document_text_block"),
        ),
      ),
    listTextBlocks: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_document_text_blocks",
          {
            tenant: organizationId,
            key: filter.key ?? null,
            legal_entity_id: filter.legalEntityId ?? null,
          },
          (value) =>
            recordsOf(value, "list_document_text_blocks").map((row) =>
              blockOf(row, "list_document_text_blocks"),
            ),
        ),
      ),
    resolveTemplate: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "resolve_document_template",
          {
            tenant: organizationId,
            document_type: input.documentType,
            legal_entity_id: input.legalEntityId ?? null,
            language: input.language ?? null,
            name: input.name ?? "default",
          },
          (value) =>
            resolvedOf(value, "resolve_document_template") ?? undefined,
        ),
      ),
    render,
    renderHtml: (input) =>
      render(input).andThen((document) =>
        Promise.resolve(
          document.template === null
            ? err(
                dbError(
                  "not_found",
                  `no ${document.documentType} template fits this document`,
                  { hint: "DOCUMENT_TEMPLATE_MISSING" },
                ),
              )
            : renderDocumentHtml({
                documentType: document.documentType,
                template: document.template.body,
                variables: document.variables,
                blocks: document.blocks,
              }),
        ),
      ),
    freeze: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "freeze_document",
          {
            tenant: organizationId,
            document_type: input.documentType,
            document_id: input.documentId,
            language: input.language ?? null,
            template_name: input.templateName ?? null,
          },
          (value) => renderedOf(value, "freeze_document"),
        ),
      ),
    contract: (documentType) =>
      call(
        "document_template_contract",
        { document_type: documentType },
        (value): DocumentContractSummary => {
          const row = recordOf(value, "document_template_contract");

          return {
            version: Number(row["version"]),
            documentType: documentTypeOf(row["documentType"]),
            variables: recordsOf(
              row["variables"],
              "document_template_contract",
            ).map((variable) => ({
              path: textOf(variable["path"]),
              type: textOf(variable["type"]),
            })),
          };
        },
      ),
    validate: (input) =>
      call(
        "validate_document_template",
        {
          document_type: input.documentType,
          body: input.body,
          text_block: input.textBlock ?? false,
        },
        (value) =>
          recordsOf(value, "validate_document_template").map((issue) => ({
            code: issueCodeOf(issue["code"]),
            message: textOf(issue["message"]),
            tag: textOf(issue["tag"]),
          })),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "document-templates",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
