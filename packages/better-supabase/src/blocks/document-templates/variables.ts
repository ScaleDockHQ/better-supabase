/** An address with the keys the contract names; a missing part is `null`. */
export interface DocumentAddress {
  readonly line1: string | null;
  readonly line2: string | null;
  readonly postalCode: string | null;
  readonly city: string | null;
  readonly region: string | null;
  readonly country: string | null;
}

/** The legal entity that issues the document. All `null` when there is none. */
export interface DocumentEntity {
  readonly id: string | null;
  readonly code: string | null;
  readonly name: string | null;
  readonly address: DocumentAddress;
  readonly vatNumber: string | null;
  readonly cocNumber: string | null;
  readonly iban: string | null;
  readonly bic: string | null;
  readonly logoAttachmentId: string | null;
  readonly defaultCurrency: string | null;
}

/** The customer the document is for. */
export interface DocumentBuyer {
  readonly id: string | null;
  /** `company` or `person` when the buyer is a contact. */
  readonly type: string | null;
  readonly name: string | null;
  readonly email: string | null;
  readonly vatNumber: string | null;
  readonly language: string | null;
  readonly address: DocumentAddress;
}

/** The document itself. A key a type has no use for is `null`. */
export interface DocumentHeader {
  readonly id: string;
  readonly type: string;
  readonly number: string | null;
  readonly title: string | null;
  readonly status: string | null;
  /** ISO date. */
  readonly date: string | null;
  readonly currency: string | null;
  readonly language: string | null;
  readonly note: string | null;
  readonly reference: string | null;
  /** Invoices, credit notes and dunning letters. */
  readonly dueOn?: string | null;
  /** Credit notes. */
  readonly originalNumber?: string | null;
  /** Quotes. */
  readonly validUntil?: string | null;
  readonly revision?: number | null;
  /** Dunning letters. */
  readonly level?: number | null;
  /**
   * The key of the text block the dunning level names; `texts.dunning` reads
   * it.
   */
  readonly textKey?: string | null;
  /** Dunning letters and statements. */
  readonly asOf?: string | null;
}

/** One line. Amounts are minor units as text; a key the source lacks is `null`. */
export interface DocumentLine {
  readonly position: number;
  readonly description: string | null;
  readonly sku: string | null;
  readonly reference: string | null;
  readonly date: string | null;
  readonly dueOn: string | null;
  /** Decimal text such as `2.5`. */
  readonly quantity: string | null;
  readonly unitAmount: string | null;
  readonly discountBps: number | null;
  readonly discountAmount: string | null;
  readonly taxRateBps: number | null;
  readonly taxCode: string | null;
  readonly amount: string | null;
}

/** The tax of one rate and tax code. */
export interface DocumentTaxLine {
  readonly taxRateBps: number;
  readonly taxCode: string | null;
  readonly net: string;
  readonly tax: string;
  readonly gross: string;
}

/** The amounts of the document, in minor units as text. */
export interface DocumentTotals {
  readonly listTotal: string | null;
  readonly discountTotal: string | null;
  readonly subtotal: string | null;
  readonly taxTotal: string | null;
  readonly total: string | null;
  readonly paidTotal: string | null;
  readonly creditedTotal: string | null;
  readonly shippingTotal: string | null;
  readonly fee: string | null;
  readonly balance: string | null;
}

export interface DocumentPaymentTerms {
  readonly code: string | null;
  readonly name: string | null;
  readonly days: number | null;
  /** ISO date. */
  readonly dueOn: string | null;
  readonly discountBps: number | null;
  readonly discountDays: number | null;
  readonly discountDueOn: string | null;
  readonly discountAmount: string | null;
}

/** Where and how the goods go: orders and delivery notes. */
export interface DocumentShipping {
  readonly address: DocumentAddress;
  readonly carrier: string | null;
  readonly trackingNumber: string | null;
}

/**
 * The data every template of contract version 1 reads. `render_document` builds
 * it in SQL, and `DOCUMENT_VARIABLES` lists its paths. A key is added as an
 * optional one, and never removed or retyped within a version.
 */
export interface DocumentVariables {
  readonly document: DocumentHeader;
  readonly entity: DocumentEntity;
  readonly buyer: DocumentBuyer;
  readonly lines: readonly DocumentLine[];
  readonly tax_lines: readonly DocumentTaxLine[];
  readonly totals: DocumentTotals;
  readonly payment_terms: DocumentPaymentTerms;
  /** Orders and delivery notes. */
  readonly shipping?: DocumentShipping;
}
