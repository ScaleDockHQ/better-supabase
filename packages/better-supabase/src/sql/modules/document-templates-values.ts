// The document templates block's fixed values: the document types, the
// variable contract and the template grammar's names. This file imports
// nothing, so the client entry can read it without the SQL builders, and the
// SQL module renders the same contract into `document_template_contract`.

/** The documents a template can be written for. */
export const DOCUMENT_TYPES = [
  "invoice",
  "credit_note",
  "quote",
  "order",
  "dunning_letter",
  "delivery_note",
  "statement",
] as const;

export type DocumentType = (typeof DOCUMENT_TYPES)[number];

/**
 * The version of the variable contract. Adding an optional variable keeps it;
 * removing or retyping one needs the next version (architecture rule 10).
 */
export const DOCUMENT_CONTRACT_VERSION = 1;

/** The filters a placeholder can apply: `{{ totals.total | money }}`. */
export const DOCUMENT_FILTERS = ["money", "date"] as const;

export type DocumentFilter = (typeof DOCUMENT_FILTERS)[number];

/** The hint codes of a template that fails validation, first to last. */
export const DOCUMENT_TEMPLATE_ISSUES = [
  "DOCUMENT_TEMPLATE_SYNTAX",
  "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE",
  "DOCUMENT_TEMPLATE_UNKNOWN_FILTER",
] as const;

export type DocumentTemplateIssueCode =
  (typeof DOCUMENT_TEMPLATE_ISSUES)[number];

/** What a variable holds. `money` is a bigint in minor units, as text. */
export type DocumentVariableType =
  | "string"
  | "number"
  | "boolean"
  | "money"
  | "date"
  | "object"
  | "list";

export interface DocumentVariable {
  /** A dotted path; a list item's field is `list[].field`. */
  readonly path: string;
  readonly type: DocumentVariableType;
  readonly description: string;
}

/** The longest template or text block body, in characters. */
export const DOCUMENT_BODY_MAX = 200_000;

/** The pattern of a document language: `nl`, `nl-NL`. */
export const DOCUMENT_LANGUAGE_PATTERN = "^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$";

/** The pattern of a text block key, readable as `texts.<key>`. */
export const DOCUMENT_TEXT_KEY_PATTERN = "^[a-z][a-z0-9_]{0,63}$";

const v = (
  path: string,
  type: DocumentVariableType,
  description: string,
): DocumentVariable => ({ path, type, description });

const ADDRESS_FIELDS: readonly (readonly [string, string])[] = [
  ["line1", "First address line"],
  ["line2", "Second address line"],
  ["postalCode", "Postal code"],
  ["city", "City"],
  ["region", "Region or state"],
  ["country", "Two-letter country code"],
];

const address = (prefix: string, what: string): readonly DocumentVariable[] => [
  v(prefix, "object", `${what} address`),
  ...ADDRESS_FIELDS.map(([field, text]) =>
    v(`${prefix}.${field}`, "string", `${text} of the ${what} address`),
  ),
];

const ENTITY: readonly DocumentVariable[] = [
  v("entity", "object", "The legal entity that issues the document"),
  v("entity.id", "string", "Legal entity id"),
  v("entity.code", "string", "Legal entity code"),
  v("entity.name", "string", "Legal entity name"),
  ...address("entity.address", "legal entity"),
  v("entity.vatNumber", "string", "VAT number"),
  v("entity.cocNumber", "string", "Chamber of commerce number"),
  v("entity.iban", "string", "Bank account"),
  v("entity.bic", "string", "Bank identifier"),
  v("entity.logoAttachmentId", "string", "Attachment id of the logo"),
  v("entity.defaultCurrency", "string", "Default currency of the entity"),
];

const BUYER: readonly DocumentVariable[] = [
  v("buyer", "object", "The customer the document is for"),
  v("buyer.id", "string", "Contact id, when the buyer is a contact"),
  v("buyer.type", "string", "company or person, when the buyer is a contact"),
  v("buyer.name", "string", "Buyer name"),
  v("buyer.email", "string", "Buyer email"),
  v("buyer.vatNumber", "string", "Buyer VAT number"),
  v("buyer.language", "string", "Buyer language, which picks the template"),
  ...address("buyer.address", "buyer"),
];

const SHIPPING: readonly DocumentVariable[] = [
  v("shipping", "object", "Where and how the goods go"),
  ...address("shipping.address", "delivery"),
  v("shipping.carrier", "string", "Carrier"),
  v("shipping.trackingNumber", "string", "Tracking number"),
];

const LINES: readonly DocumentVariable[] = [
  v("lines", "list", "The lines of the document"),
  v("lines[].position", "number", "Line position from 1"),
  v("lines[].description", "string", "Line description"),
  v("lines[].sku", "string", "SKU of the line"),
  v("lines[].reference", "string", "A document the line points to"),
  v("lines[].date", "date", "Date of the line"),
  v("lines[].dueOn", "date", "Due date of the line"),
  v("lines[].quantity", "string", "Quantity as decimal text"),
  v("lines[].unitAmount", "money", "Price of one unit"),
  v("lines[].discountBps", "number", "Discount in basis points"),
  v("lines[].discountAmount", "money", "Fixed discount of the line"),
  v("lines[].taxRateBps", "number", "Tax rate in basis points"),
  v("lines[].taxCode", "string", "Tax code"),
  v("lines[].amount", "money", "Line amount after discounts, before tax"),
];

const TAX_LINES: readonly DocumentVariable[] = [
  v("tax_lines", "list", "The tax per rate and tax code"),
  v("tax_lines[].taxRateBps", "number", "Tax rate in basis points"),
  v("tax_lines[].taxCode", "string", "Tax code"),
  v("tax_lines[].net", "money", "Net amount at this rate"),
  v("tax_lines[].tax", "money", "Tax at this rate"),
  v("tax_lines[].gross", "money", "Gross amount at this rate"),
];

const TOTALS: readonly DocumentVariable[] = [
  v("totals", "object", "The amounts of the document"),
  v("totals.listTotal", "money", "Total before discounts"),
  v("totals.discountTotal", "money", "Total discount"),
  v("totals.subtotal", "money", "Total after discounts, before tax"),
  v("totals.taxTotal", "money", "Total tax"),
  v("totals.total", "money", "Total including tax"),
  v("totals.paidTotal", "money", "Amount paid"),
  v("totals.creditedTotal", "money", "Amount credited"),
  v("totals.shippingTotal", "money", "Shipping charged"),
  v("totals.fee", "money", "Dunning fees"),
  v("totals.balance", "money", "Amount still open"),
];

const PAYMENT_TERMS: readonly DocumentVariable[] = [
  v("payment_terms", "object", "The payment terms of the document"),
  v("payment_terms.code", "string", "Payment terms code"),
  v("payment_terms.name", "string", "Payment terms name"),
  v("payment_terms.days", "number", "Days to pay"),
  v("payment_terms.dueOn", "date", "Due date"),
  v("payment_terms.discountBps", "number", "Early payment discount in bps"),
  v("payment_terms.discountDays", "number", "Days the discount holds"),
  v("payment_terms.discountDueOn", "date", "Last day for the discount"),
  v("payment_terms.discountAmount", "money", "Early payment discount amount"),
];

const TEXTS: readonly DocumentVariable[] = [
  v("texts", "object", "Text blocks by key; `texts.<key>` reads one"),
];

const base = (
  extra: readonly DocumentVariable[],
): readonly DocumentVariable[] => [
  v("document", "object", "The document itself"),
  v("document.id", "string", "Document id"),
  v("document.type", "string", "Document type"),
  v("document.number", "string", "Document number"),
  v("document.title", "string", "Title"),
  v("document.status", "string", "Status"),
  v("document.date", "date", "Document date"),
  v("document.currency", "string", "Currency code"),
  v("document.language", "string", "Language the document renders in"),
  v("document.note", "string", "Free note"),
  v("document.reference", "string", "Reference to an origin or a supplier"),
  ...extra,
  ...ENTITY,
  ...BUYER,
  ...LINES,
  ...TAX_LINES,
  ...TOTALS,
  ...PAYMENT_TERMS,
  ...TEXTS,
];

const invoice: readonly DocumentVariable[] = base([
  v("document.dueOn", "date", "Due date"),
]);

/** The variables of each document type, contract version 1. */
export const DOCUMENT_VARIABLES: Readonly<
  Record<DocumentType, readonly DocumentVariable[]>
> = {
  invoice,
  credit_note: [
    ...invoice,
    v("document.originalNumber", "string", "Number of the credited invoice"),
  ],
  quote: base([
    v("document.validUntil", "date", "Last day the quote holds"),
    v("document.revision", "number", "Revision of the quote"),
  ]),
  order: base([...SHIPPING]),
  dunning_letter: base([
    v("document.dueOn", "date", "Oldest due date in the letter"),
    v("document.level", "number", "Dunning level"),
    v(
      "document.textKey",
      "string",
      "Key of the text block the dunning level names; render_document returns it as texts.dunning",
    ),
    v("document.asOf", "date", "Date the balances are counted at"),
  ]),
  delivery_note: base([...SHIPPING]),
  statement: base([
    v("document.asOf", "date", "Date the balances are counted at"),
  ]),
};

/**
 * The contract of one type as JSON, the shape `document_template_contract`
 * returns.
 */
export function documentContract(type: DocumentType): {
  readonly version: number;
  readonly documentType: DocumentType;
  readonly variables: readonly DocumentVariable[];
} {
  return {
    version: DOCUMENT_CONTRACT_VERSION,
    documentType: type,
    variables: DOCUMENT_VARIABLES[type],
  };
}
