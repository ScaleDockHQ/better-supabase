/** A Peppol participant id: an ICD scheme from the EAS code list and the id. */
export interface EInvoiceEndpoint {
  /** The Electronic Address Scheme code, such as `0106` for a Dutch KVK number. */
  readonly scheme: string;
  readonly id: string;
}

export interface EInvoiceAddress {
  readonly street?: string;
  readonly additionalStreet?: string;
  readonly city?: string;
  readonly postalCode?: string;
  readonly region?: string;
  /** ISO 3166-1 alpha-2, such as `NL`. */
  readonly country: string;
}

/** The seller or the buyer of an e-invoice (EN 16931 BG-4 and BG-7). */
export interface EInvoiceParty {
  /** The trading name; also the legal name unless `legalName` is set. */
  readonly name: string;
  /** Where the network delivers the document (BT-34, BT-49). */
  readonly endpoint: EInvoiceEndpoint;
  readonly address: EInvoiceAddress;
  /** The VAT number with its country prefix, such as `NL123456789B01`. */
  readonly vatId?: string;
  readonly legalName?: string;
  /** The company registration, such as a chamber of commerce number. */
  readonly legalId?: { readonly id: string; readonly scheme?: string };
  readonly contact?: {
    readonly name?: string;
    readonly phone?: string;
    readonly email?: string;
  };
}
