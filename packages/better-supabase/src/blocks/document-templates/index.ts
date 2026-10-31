export {
  createDocumentTemplates,
  type DocumentContractSummary,
  type DocumentTemplate,
  type DocumentTemplateSource,
  type DocumentTemplates,
  type DocumentTemplatesOptions,
  type DocumentTextBlock,
  type FreezeDocumentInput,
  type RenderDocumentInput,
  type RenderedDocument,
  type ResolvedDocumentTemplate,
  type SaveDocumentTemplateInput,
  type SaveDocumentTextBlockInput,
} from "./document-templates.ts";

export {
  escapeHtml,
  formatDocumentDate,
  formatDocumentMoney,
  renderDocumentHtml,
  validateDocumentTemplate,
  validateDocumentTextBlock,
  type DocumentTemplateIssue,
  type RenderDocumentInput as RenderDocumentHtmlInput,
} from "./template.ts";

export type {
  DocumentAddress,
  DocumentBuyer,
  DocumentEntity,
  DocumentHeader,
  DocumentLine,
  DocumentPaymentTerms,
  DocumentShipping,
  DocumentTaxLine,
  DocumentTotals,
  DocumentVariables,
} from "./variables.ts";

export {
  DOCUMENT_CONTRACT_VERSION,
  DOCUMENT_FILTERS,
  DOCUMENT_TEMPLATE_ISSUES,
  DOCUMENT_TYPES,
  DOCUMENT_VARIABLES,
  documentContract,
  type DocumentType,
  type DocumentVariable,
  type DocumentVariableType,
} from "../../sql/modules/document-templates-values.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
} from "../../core/block-hooks.ts";

export type {
  BlockHooks,
  BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport, RpcClient } from "../../core/block-transport.ts";

export { documentTemplatesBlock } from "./manifest.ts";

export { documentTemplatesEvents } from "./events.ts";

export type {
  DocumentSnapshotEventData,
  DocumentTemplateEventData,
  DocumentTemplatesEvents,
  DocumentTextBlockEventData,
} from "./events.ts";
