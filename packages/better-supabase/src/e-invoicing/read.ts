import type { InvoiceInput, LineInput } from "../blocks/invoices/invoices.ts";
import type { Money } from "../commerce/money.ts";
import type { EInvoiceParty } from "./party.ts";

import { isCurrency, money, parseMoney } from "../commerce/money.ts";
import { isRecord } from "../core/block-helpers.ts";
import { importOptionalPeer, memoized } from "../core/optional-peer.ts";
import { temporal } from "../core/temporal-required.ts";

type Tree = Readonly<Record<string, unknown>>;

/** The part of `fast-xml-parser` that `fromUbl` uses. */
export interface XmlParserModule {
  readonly XMLParser: new (options: Readonly<Record<string, unknown>>) => {
    parse(xml: string): unknown;
  };
}

export interface FromUblOptions {
  /** The `fast-xml-parser` module, instead of loading it on first use. */
  readonly xmlParser?: XmlParserModule;
}

/** A received UBL invoice or credit note, ready to create as a purchase bill. */
export interface UblBill {
  readonly kind: "invoice" | "credit_note";
  /** The supplier's document number (BT-1). */
  readonly identifier: string;
  readonly issuedOn: Temporal.PlainDate;
  readonly dueOn?: Temporal.PlainDate;
  readonly currency: string;
  /** The supplier; match it to a company before you create the bill. */
  readonly seller: EInvoiceParty;
  readonly buyer: EInvoiceParty;
  /** For a credit note: the invoice it credits (BT-25). */
  readonly billingReference?: string;
  readonly orderReference?: string;
  /** `invoices.create` input: a purchase bill with the supplier reference. */
  readonly input: InvoiceInput;
  /** The lines; discounts and charges on the whole document become lines. */
  readonly lines: readonly LineInput[];
  readonly taxTotal: Money;
  /** What the document says is due (BT-115). */
  readonly payable: Money;
}

function isParserModule(value: unknown): value is XmlParserModule {
  return isRecord(value) && typeof value["XMLParser"] === "function";
}

const loadParser = memoized(async (): Promise<XmlParserModule> => {
  const module = await importOptionalPeer("fast-xml-parser");

  if (isParserModule(module)) {
    return module;
  }

  if (isRecord(module) && isParserModule(module["default"])) {
    return module["default"];
  }

  throw new TypeError(
    "fromUbl needs the fast-xml-parser package: pnpm add fast-xml-parser, or pass it as options.xmlParser",
  );
});

/** The keys that hold a string, for `exactOptionalPropertyTypes`. */
function defined<K extends string>(
  values: Readonly<Record<K, string | undefined>>,
): Partial<Record<K, string>> {
  const kept: Partial<Record<K, string>> = {};

  // SAFETY: Object.entries returns the keys of `values`, which are K.
  for (const [key, value] of Object.entries(values) as [
    K,
    string | undefined,
  ][]) {
    if (value !== undefined) {
      kept[key] = value;
    }
  }

  return kept;
}

const first = (value: unknown): unknown =>
  Array.isArray(value) ? value[0] : value;

function child(tree: unknown, key: string): Tree | undefined {
  const found = first(isRecord(tree) ? tree[key] : undefined);

  return isRecord(found) ? found : undefined;
}

function children(tree: unknown, key: string): Tree[] {
  const found = isRecord(tree) ? tree[key] : undefined;
  const all = Array.isArray(found) ? found : [found];

  return all.filter(isRecord);
}

function textOf(value: unknown): string | undefined {
  const found = first(value);

  if (typeof found === "string" || typeof found === "number") {
    const text = String(found).trim();

    return text === "" ? undefined : text;
  }

  return isRecord(found) ? textOf(found["#text"]) : undefined;
}

const text = (tree: unknown, key: string): string | undefined =>
  textOf(isRecord(tree) ? tree[key] : undefined);

const attribute = (
  tree: unknown,
  key: string,
  name: string,
): string | undefined => {
  const found = first(isRecord(tree) ? tree[key] : undefined);

  return isRecord(found) ? textOf(found[`@${name}`]) : undefined;
};

function required(tree: unknown, key: string, what: string): string {
  const found = text(tree, key);

  if (found === undefined) {
    throw new TypeError(`fromUbl: the document has no ${what} (${key})`);
  }

  return found;
}

function partyOf(tree: unknown, role: string): EInvoiceParty {
  const party = child(child(tree, role), "Party");

  if (party === undefined) {
    throw new TypeError(`fromUbl: the document has no ${role}`);
  }

  const address = child(party, "PostalAddress");
  const legal = child(party, "PartyLegalEntity");
  const contact = child(party, "Contact");

  const vat = children(party, "PartyTaxScheme").find(
    (scheme) => text(child(scheme, "TaxScheme"), "ID") === "VAT",
  );

  const legalId = text(legal, "CompanyID");
  const legalScheme = attribute(legal, "CompanyID", "schemeID");
  const vatId = text(vat, "CompanyID");
  const legalName = text(legal, "RegistrationName");
  const name = text(child(party, "PartyName"), "Name") ?? legalName;

  if (name === undefined) {
    throw new TypeError(`fromUbl: the ${role} has no name`);
  }

  const contactFields = defined({
    name: text(contact, "Name"),
    phone: text(contact, "Telephone"),
    email: text(contact, "ElectronicMail"),
  });

  return {
    name,
    endpoint: {
      scheme: attribute(party, "EndpointID", "schemeID") ?? "",
      id: required(party, "EndpointID", `${role} endpoint`),
    },
    address: {
      ...defined({
        street: text(address, "StreetName"),
        additionalStreet: text(address, "AdditionalStreetName"),
        city: text(address, "CityName"),
        postalCode: text(address, "PostalZone"),
        region: text(address, "CountrySubentity"),
      }),
      country: text(child(address, "Country"), "IdentificationCode") ?? "",
    },
    ...defined({
      vatId,
      legalName: legalName === name ? undefined : legalName,
    }),
    ...(legalId === undefined
      ? {}
      : { legalId: { id: legalId, ...defined({ scheme: legalScheme }) } }),
    ...(Object.keys(contactFields).length === 0
      ? {}
      : { contact: contactFields }),
  };
}

/** A UBL amount in minor units, or `undefined` when it has more decimals. */
function exact(value: string | undefined, currency: string): Money | undefined {
  if (value === undefined) {
    return undefined;
  }

  try {
    return parseMoney(value, currency);
  } catch {
    return undefined;
  }
}

function amount(tree: unknown, key: string, currency: string): Money {
  const value = required(tree, key, key);
  const found = exact(value, currency);

  if (found === undefined) {
    throw new TypeError(
      `fromUbl: ${key} "${value}" is not an amount in ${currency}`,
    );
  }

  return found;
}

/** A percentage as basis points: `21` is 2100. */
const bpsOf = (value: string | undefined): number =>
  value === undefined ? 0 : Math.round(Number(value) * 100);

interface TaxOf {
  readonly taxRateBps: number;
  readonly taxCode?: string;
}

function taxOf(category: Tree | undefined): TaxOf {
  const code = text(category, "ID");
  const taxRateBps = bpsOf(text(category, "Percent"));

  return code === undefined ? { taxRateBps } : { taxRateBps, taxCode: code };
}

const roundDiv = (numerator: bigint, denominator: bigint): bigint => {
  const negative = numerator < 0n;
  const n = negative ? -numerator : numerator;
  const rounded = (n * 2n + denominator) / (denominator * 2n);

  return negative ? -rounded : rounded;
};

function scaled(value: string): { digits: bigint; scale: bigint } | undefined {
  const match = /^(-?)(\d+)(?:\.(\d+))?$/.exec(value);

  if (match === null) {
    return undefined;
  }

  const [, sign = "", whole = "0", fraction = ""] = match;

  return {
    digits: BigInt(`${sign}${whole}${fraction}`),
    scale: 10n ** BigInt(fraction.length),
  };
}

/**
 * A line kept with its quantity and price when the block's rounding gives the
 * same net amount, and otherwise as one unit of its net amount.
 */
function lineOf(line: Tree, credit: boolean, currency: string): LineInput {
  const item = child(line, "Item");
  const price = child(line, "Price");
  const net = amount(line, "LineExtensionAmount", currency);

  const quantityText =
    text(line, credit ? "CreditedQuantity" : "InvoicedQuantity") ?? "1";

  const quantity = scaled(quantityText);
  const unit = exact(text(price, "PriceAmount"), currency);
  const base = text(price, "BaseQuantity");
  const description = text(item, "Name") ?? text(item, "Description") ?? "Line";
  const tax = taxOf(child(item, "ClassifiedTaxCategory"));

  const lumped: LineInput = {
    description,
    quantity: 1,
    unitAmount: net,
    ...tax,
  };

  if (
    quantity === undefined ||
    unit === undefined ||
    (base !== undefined && Number(base) !== 1)
  ) {
    return lumped;
  }

  const list = roundDiv(quantity.digits * unit.amount, quantity.scale);
  let allowance = 0n;

  for (const part of children(line, "AllowanceCharge")) {
    const value = amount(part, "Amount", currency).amount;

    if (text(part, "ChargeIndicator") === "true") {
      return lumped;
    }

    allowance += value;
  }

  const discountBps = list === 0n ? 0 : Number((allowance * 10_000n) / list);

  const counted = list - roundDiv(list * BigInt(discountBps), 10_000n);

  if (counted !== net.amount || Number(quantityText) <= 0) {
    return lumped;
  }

  return {
    description,
    quantity: Number(quantityText),
    unitAmount: unit,
    ...(discountBps === 0 ? {} : { discountBps }),
    ...tax,
  };
}

function documentLines(root: Tree, currency: string): LineInput[] {
  return children(root, "AllowanceCharge").map((part) => {
    const charge = text(part, "ChargeIndicator") === "true";
    const value = amount(part, "Amount", currency);

    return {
      description:
        text(part, "AllowanceChargeReason") ?? (charge ? "Charge" : "Discount"),
      quantity: 1,
      unitAmount: charge ? value : money(-value.amount, currency),
      ...taxOf(child(part, "TaxCategory")),
    };
  });
}

/**
 * Reads a UBL 2.1 invoice or credit note, such as a Peppol BIS Billing 3.0
 * document, into the input of a purchase bill. Loads `fast-xml-parser` on first
 * use; it reads the document only and does not validate it.
 */
export async function fromUbl(
  xml: string,
  options: FromUblOptions = {},
): Promise<UblBill> {
  const parserModule = options.xmlParser ?? (await loadParser());

  const parser = new parserModule.XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: "@",
    removeNSPrefix: true,
    parseTagValue: false,
    parseAttributeValue: false,
    processEntities: true,
  });

  const parsed = parser.parse(xml);
  const invoice = child(parsed, "Invoice");
  const creditNote = child(parsed, "CreditNote");
  const root = invoice ?? creditNote;

  if (root === undefined) {
    throw new TypeError(
      "fromUbl: the document is not a UBL Invoice or CreditNote",
    );
  }

  const credit =
    creditNote !== undefined || text(root, "InvoiceTypeCode") === "381";

  const currency = required(root, "DocumentCurrencyCode", "currency");

  if (!isCurrency(currency)) {
    throw new TypeError(
      `fromUbl: ${JSON.stringify(currency)} is not an ISO 4217 currency`,
    );
  }

  const identifier = required(root, "ID", "number");
  const { PlainDate } = temporal();

  const issuedOn = PlainDate.from(required(root, "IssueDate", "issue date"));

  const due =
    text(root, "DueDate") ??
    text(child(root, "PaymentMeans"), "PaymentDueDate");

  const dueOn = due === undefined ? undefined : PlainDate.from(due);
  const seller = partyOf(root, "AccountingSupplierParty");
  const buyer = partyOf(root, "AccountingCustomerParty");
  const note = text(root, "Note");
  const totals = child(root, "LegalMonetaryTotal");

  const billingReference = text(
    child(child(root, "BillingReference"), "InvoiceDocumentReference"),
    "ID",
  );

  const orderReference = text(child(root, "OrderReference"), "ID");

  const lines = [
    ...children(root, creditNote ? "CreditNoteLine" : "InvoiceLine").map(
      (line) => lineOf(line, creditNote !== undefined, currency),
    ),
    ...documentLines(root, currency),
  ];

  const termsDays =
    dueOn === undefined ? undefined : issuedOn.until(dueOn).days;

  const input: InvoiceInput = {
    title: `${seller.name} ${identifier}`,
    direction: "purchase",
    supplierReference: identifier,
    currency,
    ...(termsDays === undefined || termsDays < 0 ? {} : { termsDays }),
    ...(note === undefined ? {} : { note }),
  };

  return {
    kind: credit ? "credit_note" : "invoice",
    identifier,
    issuedOn,
    ...(dueOn === undefined ? {} : { dueOn }),
    currency,
    seller,
    buyer,
    ...(billingReference === undefined ? {} : { billingReference }),
    ...(orderReference === undefined ? {} : { orderReference }),
    input,
    lines,
    taxTotal: amount(child(root, "TaxTotal"), "TaxAmount", currency),
    payable: amount(totals, "PayableAmount", currency),
  };
}
