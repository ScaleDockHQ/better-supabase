import type { Invoice, Line } from "../blocks/invoices/invoices.ts";
import type { Money } from "../commerce/money.ts";
import type { EInvoiceDocument } from "./channel.ts";
import type { EInvoiceParty } from "./party.ts";
import type { Child } from "./xml.ts";

import { allocateMoney, money, toDecimal } from "../commerce/money.ts";
import { el } from "./xml.ts";

/** The EN 16931 specification identifier of Peppol BIS Billing 3.0 (BT-24). */
export const PEPPOL_BIS_CUSTOMIZATION =
  "urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0";

/** The Peppol business process of a billing document (BT-23). */
export const PEPPOL_BIS_PROFILE = "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0";

const NAMESPACE = {
  Invoice: "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2",
  CreditNote: "urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2",
  cac: "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2",
  cbc: "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2",
} as const;

/** UNCL 5305 VAT category codes that EN 16931 allows (BT-118, BT-151). */
export type TaxCategoryCode =
  | "S"
  | "Z"
  | "E"
  | "AE"
  | "K"
  | "G"
  | "O"
  | "L"
  | "M";

const CATEGORIES: ReadonlySet<string> = new Set([
  "S",
  "Z",
  "E",
  "AE",
  "K",
  "G",
  "O",
  "L",
  "M",
]);

/** The categories EN 16931 requires an exemption reason for (BR-E-10 and on). */
const EXEMPTIONS: Readonly<
  Partial<Record<TaxCategoryCode, { code?: string; reason: string }>>
> = {
  E: { reason: "Exempt from VAT" },
  AE: { code: "VATEX-EU-AE", reason: "Reverse charge" },
  K: { code: "VATEX-EU-IC", reason: "Intra-Community supply" },
  G: { code: "VATEX-EU-G", reason: "Export outside the EU" },
  O: { code: "VATEX-EU-O", reason: "Not subject to VAT" },
};

/** The invoice fields `toUbl` reads; an `Invoice` from the invoices block fits. */
export type UblSource = Pick<
  Invoice,
  | "kind"
  | "identifier"
  | "issuedOn"
  | "dueOn"
  | "currency"
  | "lines"
  | "totals"
  | "termsDays"
  | "pricesIncludeTax"
> &
  Partial<Pick<Invoice, "note">>;

export interface UblOptions {
  readonly seller: EInvoiceParty;
  readonly buyer: EInvoiceParty;
  /**
   * The buyer's reference (BT-10). Peppol needs it or `orderReference`;
   * defaults to the invoice identifier.
   */
  readonly buyerReference?: string;
  /** The buyer's purchase order number (BT-13). */
  readonly orderReference?: string;
  /** For a credit note: the identifier of the invoice it credits (BT-25). */
  readonly billingReference?: string;
  /** How the buyer pays (BG-16). `58` (SEPA credit transfer) with an IBAN. */
  readonly payment?: {
    readonly code?: string;
    readonly iban?: string;
    readonly bic?: string;
    readonly accountName?: string;
    /** The remittance reference (BT-83); defaults to the invoice identifier. */
    readonly paymentId?: string;
  };
  /** Payment terms text (BT-20); defaults to the invoice's terms in days. */
  readonly paymentTerms?: string;
  /** The UN/ECE Recommendation 20 unit of every line. Default `C62` (one). */
  readonly unitCode?: string;
  /**
   * The VAT category of a line. Defaults to the line's `taxCode` when it is a
   * UNCL 5305 code, then `S` for a rate above 0 and `Z` for 0.
   */
  readonly taxCategory?: (line: Line) => TaxCategoryCode;
  /** Exemption reasons per category, over the defaults. */
  readonly exemptions?: Partial<
    Record<TaxCategoryCode, { readonly code?: string; readonly reason: string }>
  >;
}

/** Halves round away from zero, as Postgres rounds `numeric`. */
function roundDiv(numerator: bigint, denominator: bigint): bigint {
  const negative = numerator < 0n !== denominator < 0n;
  const n = numerator < 0n ? -numerator : numerator;
  const d = denominator < 0n ? -denominator : denominator;
  const rounded = (n * 2n + d) / (d * 2n);

  return negative ? -rounded : rounded;
}

/** A quantity as an exact decimal: digits over a power of ten. */
function decimalOf(value: number): { digits: bigint; scale: bigint } {
  const text = Number.isInteger(value) ? String(value) : value.toFixed(10);
  const [whole = "0", fraction = ""] = text.split(".");
  const trimmed = fraction.replace(/0+$/, "");

  return {
    digits: BigInt(whole + trimmed),
    scale: 10n ** BigInt(trimmed.length),
  };
}

const quantityText = (value: number): string => {
  const { digits, scale } = decimalOf(value);
  const units = scale.toString().length - 1;

  if (units === 0) {
    return digits.toString();
  }

  const negative = digits < 0n;

  const padded = (negative ? -digits : digits)
    .toString()
    .padStart(units + 1, "0");

  return `${negative ? "-" : ""}${padded.slice(0, -units)}.${padded.slice(-units)}`;
};

/** Basis points as a percentage: 2100 is `21`, 550 is `5.5`. */
const percentText = (bps: number): string =>
  quantityText(Math.round(bps) / 100);

interface Counted {
  readonly line: Line;
  readonly category: TaxCategoryCode;
  readonly list: bigint;
  readonly discount: bigint;
  readonly net: bigint;
}

interface Group {
  readonly category: TaxCategoryCode;
  readonly rateBps: number;
  readonly net: bigint;
  allowance: bigint;
}

function categoryOf(line: Line, options: UblOptions): TaxCategoryCode {
  const given = options.taxCategory?.(line);

  if (given !== undefined) {
    return given;
  }

  const code = line.taxCode?.toUpperCase();

  if (code !== undefined && CATEGORIES.has(code)) {
    // SAFETY: CATEGORIES holds exactly the TaxCategoryCode members.
    return code as TaxCategoryCode;
  }

  return line.taxRateBps > 0 ? "S" : "Z";
}

function countLine(line: Line, options: UblOptions): Counted {
  const { digits, scale } = decimalOf(line.quantity);
  const list = roundDiv(digits * line.unitAmount.amount, scale);
  const discount = roundDiv(list * BigInt(line.discountBps), 10_000n);
  const category = categoryOf(line, options);

  if (EXEMPTIONS[category] !== undefined && line.taxRateBps !== 0) {
    throw new TypeError(
      `toUbl: VAT category ${category} needs a 0 rate, and line "${line.description}" has ${line.taxRateBps} basis points`,
    );
  }

  return { line, category, list, discount, net: list - discount };
}

function groupsOf(lines: readonly Counted[]): Group[] {
  const groups = new Map<string, Group>();

  for (const counted of lines) {
    const key = `${counted.category}:${counted.line.taxRateBps}`;
    const found = groups.get(key);

    groups.set(key, {
      category: counted.category,
      rateBps: counted.line.taxRateBps,
      net: (found?.net ?? 0n) + counted.net,
      allowance: 0n,
    });
  }

  return [...groups.values()];
}

/** Spreads the discount on the whole invoice over the VAT groups by net. */
function spreadDiscount(groups: Group[], discount: Money): void {
  if (discount.amount <= 0n || groups.length === 0) {
    return;
  }

  const weights = groups.map((group) => (group.net > 0n ? group.net : 0n));

  if (weights.every((weight) => weight === 0n)) {
    return;
  }

  for (const [index, part] of allocateMoney(discount, weights).entries()) {
    const group = groups[index];

    if (group !== undefined) {
      group.allowance = part.amount;
    }
  }
}

function party(value: EInvoiceParty): string {
  const a = value.address;

  return el("cac:Party", [
    el("cbc:EndpointID", value.endpoint.id, {
      schemeID: value.endpoint.scheme,
    }),
    el("cac:PartyName", [el("cbc:Name", value.name)]),
    el("cac:PostalAddress", [
      el("cbc:StreetName", a.street),
      el("cbc:AdditionalStreetName", a.additionalStreet),
      el("cbc:CityName", a.city),
      el("cbc:PostalZone", a.postalCode),
      el("cbc:CountrySubentity", a.region),
      el("cac:Country", [el("cbc:IdentificationCode", a.country)]),
    ]),
    value.vatId === undefined
      ? undefined
      : el("cac:PartyTaxScheme", [
          el("cbc:CompanyID", value.vatId),
          el("cac:TaxScheme", [el("cbc:ID", "VAT")]),
        ]),
    el("cac:PartyLegalEntity", [
      el("cbc:RegistrationName", value.legalName ?? value.name),
      el("cbc:CompanyID", value.legalId?.id, {
        schemeID: value.legalId?.scheme,
      }),
    ]),
    value.contact === undefined
      ? undefined
      : el("cac:Contact", [
          el("cbc:Name", value.contact.name),
          el("cbc:Telephone", value.contact.phone),
          el("cbc:ElectronicMail", value.contact.email),
        ]),
  ]);
}

/**
 * Writes an issued invoice or credit note as a UBL 2.1 document that follows EN
 * 16931 and Peppol BIS Billing 3.0. Validate it with the official Peppol
 * Schematron before you send it; better-supabase bundles no validator.
 *
 * Totals follow from the lines: VAT counts once per category and rate, and a
 * cent the invoice's own rounding differs by goes into the rounding amount, so
 * the payable amount is the invoice's total. Charges added after issue, such as
 * reminder fees, are not part of the document.
 */
export function toUbl(
  invoice: UblSource,
  options: UblOptions,
): EInvoiceDocument {
  const id = invoice.identifier;
  const issuedOn = invoice.issuedOn;

  if (id === undefined || issuedOn === undefined) {
    throw new TypeError(
      "toUbl: issue the invoice first; a draft has no number",
    );
  }

  if (invoice.pricesIncludeTax) {
    throw new TypeError(
      "toUbl: EN 16931 states net prices, and this invoice's prices include tax",
    );
  }

  const credit = invoice.kind === "credit_note";
  const root = credit ? "CreditNote" : "Invoice";
  const currency = invoice.currency;
  const amount = (value: bigint): string => toDecimal(money(value, currency));

  const amountEl = (name: string, value: bigint): string =>
    el(name, amount(value), { currencyID: currency });

  const counted = invoice.lines.map((line) => countLine(line, options));
  const groups = groupsOf(counted);
  const lineTotal = counted.reduce((sum, line) => sum + line.net, 0n);

  const lineDiscounts = counted.reduce((sum, line) => sum + line.discount, 0n);

  const documentDiscount = invoice.totals.discountTotal.amount - lineDiscounts;
  spreadDiscount(groups, money(documentDiscount, currency));

  const allowanceTotal = groups.reduce(
    (sum, group) => sum + group.allowance,
    0n,
  );

  const taxed = groups.map((group) => {
    const taxable = group.net - group.allowance;

    return {
      ...group,
      taxable,
      tax: roundDiv(taxable * BigInt(group.rateBps), 10_000n),
    };
  });

  const taxTotal = taxed.reduce((sum, group) => sum + group.tax, 0n);
  const exclusive = lineTotal - allowanceTotal;
  const inclusive = exclusive + taxTotal;
  const payable = invoice.totals.total.amount;
  const rounding = payable - inclusive;

  if ((rounding < 0n ? -rounding : rounding) > BigInt(groups.length + 1)) {
    throw new TypeError(
      `toUbl: the invoice's total ${amount(payable)} doesn't follow from its lines (${amount(inclusive)})`,
    );
  }

  const exemption = (category: TaxCategoryCode) =>
    options.exemptions?.[category] ?? EXEMPTIONS[category];

  const category = (
    name: string,
    code: TaxCategoryCode,
    rateBps: number,
    withReason: boolean,
  ): string =>
    el(name, [
      el("cbc:ID", code),
      code === "O" ? undefined : el("cbc:Percent", percentText(rateBps)),
      withReason ? el("cbc:TaxExemptionReasonCode", exemption(code)?.code) : "",
      withReason ? el("cbc:TaxExemptionReason", exemption(code)?.reason) : "",
      el("cac:TaxScheme", [el("cbc:ID", "VAT")]),
    ]);

  const payment = options.payment;
  const paymentCode = payment?.code ?? (payment?.iban ? "58" : undefined);

  const terms =
    options.paymentTerms ??
    (invoice.termsDays > 0
      ? `Payment within ${invoice.termsDays} days`
      : undefined);

  const lines: Child[] = counted.map((item, index) =>
    el(credit ? "cac:CreditNoteLine" : "cac:InvoiceLine", [
      el("cbc:ID", String(index + 1)),
      el(
        credit ? "cbc:CreditedQuantity" : "cbc:InvoicedQuantity",
        quantityText(item.line.quantity),
        { unitCode: options.unitCode ?? "C62" },
      ),
      amountEl("cbc:LineExtensionAmount", item.net),
      item.discount === 0n
        ? undefined
        : el("cac:AllowanceCharge", [
            el("cbc:ChargeIndicator", "false"),
            el("cbc:AllowanceChargeReasonCode", "95"),
            el("cbc:AllowanceChargeReason", "Discount"),
            el(
              "cbc:MultiplierFactorNumeric",
              percentText(item.line.discountBps),
            ),
            amountEl("cbc:Amount", item.discount),
            amountEl("cbc:BaseAmount", item.list),
          ]),
      el("cac:Item", [
        el("cbc:Name", item.line.description.slice(0, 1000)),
        category(
          "cac:ClassifiedTaxCategory",
          item.category,
          item.line.taxRateBps,
          false,
        ),
      ]),
      el("cac:Price", [
        el("cbc:PriceAmount", toDecimal(item.line.unitAmount), {
          currencyID: currency,
        }),
      ]),
    ]),
  );

  const body = el(root, [
    el("cbc:CustomizationID", PEPPOL_BIS_CUSTOMIZATION),
    el("cbc:ProfileID", PEPPOL_BIS_PROFILE),
    el("cbc:ID", id),
    el("cbc:IssueDate", issuedOn.toString()),
    credit ? undefined : el("cbc:DueDate", invoice.dueOn?.toString()),
    el(
      credit ? "cbc:CreditNoteTypeCode" : "cbc:InvoiceTypeCode",
      credit ? "381" : "380",
    ),
    el("cbc:Note", invoice.note),
    el("cbc:DocumentCurrencyCode", currency),
    el("cbc:BuyerReference", options.buyerReference ?? id),
    options.orderReference === undefined
      ? undefined
      : el("cac:OrderReference", [el("cbc:ID", options.orderReference)]),
    options.billingReference === undefined
      ? undefined
      : el("cac:BillingReference", [
          el("cac:InvoiceDocumentReference", [
            el("cbc:ID", options.billingReference),
          ]),
        ]),
    el("cac:AccountingSupplierParty", [party(options.seller)]),
    el("cac:AccountingCustomerParty", [party(options.buyer)]),
    paymentCode === undefined
      ? undefined
      : el("cac:PaymentMeans", [
          el("cbc:PaymentMeansCode", paymentCode),
          el("cbc:PaymentID", payment?.paymentId ?? id),
          payment?.iban === undefined
            ? undefined
            : el("cac:PayeeFinancialAccount", [
                el("cbc:ID", payment.iban.replaceAll(" ", "")),
                el("cbc:Name", payment.accountName),
                payment.bic === undefined
                  ? undefined
                  : el("cac:FinancialInstitutionBranch", [
                      el("cbc:ID", payment.bic),
                    ]),
              ]),
        ]),
    terms === undefined
      ? undefined
      : el("cac:PaymentTerms", [el("cbc:Note", terms)]),
    ...taxed.map((group) =>
      group.allowance === 0n
        ? undefined
        : el("cac:AllowanceCharge", [
            el("cbc:ChargeIndicator", "false"),
            el("cbc:AllowanceChargeReasonCode", "95"),
            el("cbc:AllowanceChargeReason", "Discount"),
            amountEl("cbc:Amount", group.allowance),
            category("cac:TaxCategory", group.category, group.rateBps, false),
          ]),
    ),
    el("cac:TaxTotal", [
      amountEl("cbc:TaxAmount", taxTotal),
      ...taxed.map((group) =>
        el("cac:TaxSubtotal", [
          amountEl("cbc:TaxableAmount", group.taxable),
          amountEl("cbc:TaxAmount", group.tax),
          category(
            "cac:TaxCategory",
            group.category,
            group.rateBps,
            exemption(group.category) !== undefined,
          ),
        ]),
      ),
    ]),
    el("cac:LegalMonetaryTotal", [
      amountEl("cbc:LineExtensionAmount", lineTotal),
      amountEl("cbc:TaxExclusiveAmount", exclusive),
      amountEl("cbc:TaxInclusiveAmount", inclusive),
      allowanceTotal === 0n
        ? undefined
        : amountEl("cbc:AllowanceTotalAmount", allowanceTotal),
      rounding === 0n
        ? undefined
        : amountEl("cbc:PayableRoundingAmount", rounding),
      amountEl("cbc:PayableAmount", payable),
    ]),
    ...lines,
  ]);

  const xml = `<?xml version="1.0" encoding="UTF-8"?>\n${body.replace(
    `<${root}>`,
    `<${root} xmlns="${NAMESPACE[root]}" xmlns:cac="${NAMESPACE.cac}" xmlns:cbc="${NAMESPACE.cbc}">`,
  )}\n`;

  return { type: root, id, xml };
}
