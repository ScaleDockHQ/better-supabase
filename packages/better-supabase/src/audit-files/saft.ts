import type {
  AuditAccountType,
  AuditBooks,
  AuditEntry,
  AuditFileAdapter,
  AuditFileSource,
  AuditJournalType,
  AuditParseOptions,
  AuditRecord,
} from "./model.ts";
import type { WalkSpec, XmlNode } from "./xml.ts";

import { SPEC_PINS } from "../core/spec-pins.ts";
import { AuditFileError, defineAuditFileAdapter } from "./model.ts";
import {
  amountChild,
  controlTotals,
  formatAmount,
  parseAmount,
  parseDate,
  requiredText,
  sides,
  WarningLog,
} from "./support.ts";
import { childNode, childrenOf, childText, tag, walk, wrap } from "./xml.ts";

/** The namespace of the OECD SAF-T 2.00 schema. */
export const SAFT_NAMESPACE = "urn:OECD:StandardAuditFile-Taxation/2.00";

export interface SaftOptions {
  /** The type of a tax code; the file does not say. Default `sales`. */
  readonly taxCodeType?: "sales" | "purchase";
  /**
   * Maps the file's `AccountType` text to a type. Return `undefined` to let the
   * adapter pick `asset` and warn.
   */
  readonly accountType?: (
    raw: string | undefined,
    code: string,
  ) => AuditAccountType | undefined;
  /** Maps the journal `Type` text. Default: by keyword, else `general`. */
  readonly journalType?: (raw: string | undefined) => AuditJournalType;
  /** `AuditFileDateCreated` of an export, `YYYY-MM-DD`; default today. */
  readonly createdOn?: string;
}

const ROOT = "AuditFile";
const MASTER = `${ROOT}/MasterFiles`;
const ACCOUNT = `${MASTER}/GeneralLedgerAccounts/Account`;
const CUSTOMER = `${MASTER}/Customers/Customer`;
const SUPPLIER = `${MASTER}/Suppliers/Supplier`;
const TAX = `${MASTER}/TaxTable/TaxTableEntry`;
const LEDGER = `${ROOT}/GeneralLedgerEntries`;
const JOURNAL = `${LEDGER}/Journal`;
const TRANSACTION = `${JOURNAL}/Transaction`;

const set = (...paths: string[]): ReadonlySet<string> => new Set(paths);

const SPEC: WalkSpec = {
  records: new Map<string, ReadonlySet<string>>([
    [
      `${ROOT}/Header`,
      set(
        "AuditFileVersion",
        "AuditFileCountry",
        "AuditFileDateCreated",
        "SoftwareCompanyName",
        "SoftwareID",
        "SoftwareVersion",
        "Company",
        "Company/RegistrationNumber",
        "Company/Name",
        "DefaultCurrencyCode",
        "SelectionCriteria",
        "SelectionCriteria/SelectionStartDate",
        "SelectionCriteria/SelectionEndDate",
        "SelectionCriteria/PeriodStartYear",
        "TaxRegistrationNumber",
      ),
    ],
    [
      ACCOUNT,
      set(
        "AccountID",
        "AccountDescription",
        "AccountType",
        "AccountCreationDate",
        "OpeningDebitBalance",
        "OpeningCreditBalance",
        "ClosingDebitBalance",
        "ClosingCreditBalance",
      ),
    ],
    [
      CUSTOMER,
      set(
        "CustomerID",
        "AccountID",
        "CustomerTaxID",
        "CompanyName",
        "Name",
        "OpeningDebitBalance",
        "OpeningCreditBalance",
        "ClosingDebitBalance",
        "ClosingCreditBalance",
      ),
    ],
    [
      SUPPLIER,
      set(
        "SupplierID",
        "AccountID",
        "SupplierTaxID",
        "CompanyName",
        "Name",
        "OpeningDebitBalance",
        "OpeningCreditBalance",
        "ClosingDebitBalance",
        "ClosingCreditBalance",
      ),
    ],
    [
      TAX,
      set(
        "TaxType",
        "Description",
        "TaxCodeDetails",
        "TaxCodeDetails/TaxCode",
        "TaxCodeDetails/Description",
        "TaxCodeDetails/TaxPercentage",
      ),
    ],
    [
      TRANSACTION,
      set(
        "TransactionID",
        "Period",
        "PeriodYear",
        "TransactionDate",
        "Description",
        "SystemEntryDate",
        "GLPostingDate",
        "CustomerID",
        "SupplierID",
        "Line",
        "Line/RecordID",
        "Line/AccountID",
        "Line/CustomerID",
        "Line/SupplierID",
        "Line/Description",
        "Line/SourceDocumentID",
        "Line/DebitAmount",
        "Line/DebitAmount/Amount",
        "Line/CreditAmount",
        "Line/CreditAmount/Amount",
        "Line/TaxInformation",
        "Line/TaxInformation/TaxCode",
        "Line/TaxInformation/TaxAmount",
        "Line/TaxInformation/TaxAmount/Amount",
      ),
    ],
  ]),
  containers: set(
    ROOT,
    MASTER,
    `${MASTER}/GeneralLedgerAccounts`,
    `${MASTER}/Customers`,
    `${MASTER}/Suppliers`,
    `${MASTER}/TaxTable`,
    LEDGER,
    JOURNAL,
  ),
  leaves: set(
    `${LEDGER}/NumberOfEntries`,
    `${LEDGER}/TotalDebit`,
    `${LEDGER}/TotalCredit`,
    `${JOURNAL}/JournalID`,
    `${JOURNAL}/Description`,
    `${JOURNAL}/Type`,
  ),
};

const ACCOUNT_TYPES: Readonly<Record<string, AuditAccountType>> = {
  asset: "asset",
  assets: "asset",
  bank: "asset",
  liability: "liability",
  liabilities: "liability",
  equity: "equity",
  income: "income",
  revenue: "income",
  expense: "expense",
  expenses: "expense",
  cost: "expense",
};

const SELLING = /sale|verkoop|revenue|income/iu;
const BUYING = /purchase|buy|inkoop|expense/iu;
const BANK = /bank|giro/iu;
const CASH = /cash|kas/iu;

/** The journal type for free text such as `Sales` or `Bank`. */
function journalTypeOf(raw: string | undefined): AuditJournalType {
  if (raw === undefined) {
    return "general";
  }

  if (BANK.test(raw)) {
    return "bank";
  }

  if (CASH.test(raw)) {
    return "cash";
  }

  if (SELLING.test(raw)) {
    return "sales";
  }

  if (BUYING.test(raw)) {
    return "purchase";
  }

  return "general";
}

const rateBpsOf = (text: string, where: string): number =>
  Number(parseAmount(text, 2, where));

function readHeader(node: XmlNode): AuditRecord {
  const selection = childNode(node, "SelectionCriteria");

  const start =
    selection === undefined
      ? undefined
      : childText(selection, "SelectionStartDate");

  const end =
    selection === undefined
      ? undefined
      : childText(selection, "SelectionEndDate");

  if (start === undefined || end === undefined) {
    throw new AuditFileError(
      "AUDIT_FILE_INVALID",
      "the Header has no SelectionCriteria with SelectionStartDate and SelectionEndDate",
    );
  }

  const startDate = parseDate(start, "SelectionStartDate");

  const stated =
    selection === undefined
      ? undefined
      : childText(selection, "PeriodStartYear");

  const company = childNode(node, "Company");

  const registration =
    company === undefined
      ? undefined
      : childText(company, "RegistrationNumber");

  const country = childText(node, "AuditFileCountry");
  const taxId = childText(node, "TaxRegistrationNumber");
  const softwareName = childText(node, "SoftwareCompanyName");
  const softwareVersion = childText(node, "SoftwareVersion");

  return {
    kind: "header",
    header: {
      fiscalYear:
        stated === undefined ? Number(startDate.slice(0, 4)) : Number(stated),
      startDate,
      endDate: parseDate(end, "SelectionEndDate"),
      currency: childText(node, "DefaultCurrencyCode") ?? "EUR",
      company: {
        name: company === undefined ? "" : (childText(company, "Name") ?? ""),
        ...(registration === undefined
          ? {}
          : { registrationNumber: registration }),
        ...(taxId === undefined ? {} : { taxId }),
        ...(country === undefined ? {} : { country }),
      },
      ...(softwareName === undefined && softwareVersion === undefined
        ? {}
        : {
            software: {
              ...(softwareName === undefined ? {} : { name: softwareName }),
              ...(softwareVersion === undefined
                ? {}
                : { version: softwareVersion }),
            },
          }),
    },
  };
}

function openingOf(
  node: XmlNode,
  fiscalYear: number,
  accountCode: string,
  partyCode: string | undefined,
  decimals: number | undefined,
): AuditRecord | undefined {
  const debit =
    amountChild(
      node,
      "OpeningDebitBalance",
      decimals,
      `${accountCode} opening`,
    ) ?? 0n;

  const credit =
    amountChild(
      node,
      "OpeningCreditBalance",
      decimals,
      `${accountCode} opening`,
    ) ?? 0n;

  const amount = debit - credit;

  return amount === 0n
    ? undefined
    : {
        kind: "openingBalance",
        balance: {
          fiscalYear,
          accountCode,
          ...(partyCode === undefined ? {} : { partyCode }),
          amount,
        },
      };
}

async function* parse(
  options: SaftOptions,
  source: AuditFileSource,
  parseOptions: AuditParseOptions = {},
): AsyncGenerator<AuditRecord> {
  const decimals = parseOptions.decimals;
  const log = new WarningLog();
  let fiscalYear: number | undefined;

  let journal: { code?: string; name?: string; type?: string; sent: boolean } =
    { sent: false };

  let debitTotal = 0n;
  let creditTotal = 0n;
  let statedDebit: bigint | undefined;
  let statedCredit: bigint | undefined;

  const year = (): number => {
    if (fiscalYear === undefined) {
      throw new AuditFileError(
        "AUDIT_FILE_INVALID",
        "the Header must come before the master files",
      );
    }

    return fiscalYear;
  };

  const journalRecord = (): AuditRecord | undefined => {
    if (journal.sent || journal.code === undefined) {
      return undefined;
    }

    journal.sent = true;

    return {
      kind: "journal",
      journal: {
        code: journal.code,
        name: journal.name ?? journal.code,
        type: (options.journalType ?? journalTypeOf)(journal.type),
      },
    };
  };

  for await (const event of walk(source, SPEC, parseOptions)) {
    if (event.type === "unmapped") {
      log.unmapped(event.path);
    } else if (event.type === "open" && event.path === JOURNAL) {
      journal = { sent: false };
    } else if (event.type === "close" && event.path === JOURNAL) {
      const record = journalRecord();

      if (record !== undefined) {
        yield record;
      }
    } else if (event.type === "leaf") {
      const name = event.path.slice(event.path.lastIndexOf("/") + 1);

      if (event.path === `${JOURNAL}/JournalID`) {
        journal.code = event.text;
      } else if (event.path === `${JOURNAL}/Description`) {
        journal.name = event.text;
      } else if (event.path === `${JOURNAL}/Type`) {
        journal.type = event.text;
      } else if (name === "TotalDebit" && event.text !== "") {
        statedDebit = parseAmount(event.text, decimals, "TotalDebit");
      } else if (name === "TotalCredit" && event.text !== "") {
        statedCredit = parseAmount(event.text, decimals, "TotalCredit");
      }
    } else if (event.type === "node") {
      const { node } = event;

      if (event.path === `${ROOT}/Header`) {
        const record = readHeader(node);

        if (record.kind === "header") {
          fiscalYear = record.header.fiscalYear;
        }

        yield record;
      } else if (event.path === ACCOUNT) {
        const code = requiredText(node, "AccountID", "an Account");
        const raw = childText(node, "AccountType");

        const mapped = (
          options.accountType ??
          ((text) =>
            text === undefined ? undefined : ACCOUNT_TYPES[text.toLowerCase()])
        )(raw, code);

        if (mapped === undefined) {
          log.add(
            "AUDIT_ACCOUNT_TYPE_ASSUMED",
            "an account has no known AccountType; it was imported as an asset",
          );
        }

        yield {
          kind: "account",
          account: {
            code,
            name: childText(node, "AccountDescription") ?? code,
            type: mapped ?? "asset",
            ...(mapped === undefined ? { typeAssumed: true } : {}),
          },
        };

        const opening = openingOf(node, year(), code, undefined, decimals);

        if (opening !== undefined) {
          yield opening;
        }
      } else if (event.path === CUSTOMER || event.path === SUPPLIER) {
        const customer = event.path === CUSTOMER;

        const code = requiredText(
          node,
          customer ? "CustomerID" : "SupplierID",
          customer ? "a Customer" : "a Supplier",
        );

        const control = childText(node, "AccountID");

        const taxId = childText(
          node,
          customer ? "CustomerTaxID" : "SupplierTaxID",
        );

        yield {
          kind: "party",
          party: {
            kind: customer ? "customer" : "supplier",
            code,
            name:
              childText(node, "CompanyName") ?? childText(node, "Name") ?? code,
            ...(taxId === undefined ? {} : { taxId }),
            ...(control === undefined ? {} : { accountCode: control }),
          },
        };

        if (control !== undefined) {
          const opening = openingOf(node, year(), control, code, decimals);

          if (opening !== undefined) {
            yield opening;
          }
        }
      } else if (event.path === TAX) {
        for (const details of childrenOf(node, "TaxCodeDetails")) {
          const code = requiredText(details, "TaxCode", "a TaxCodeDetails");
          const percentage = childText(details, "TaxPercentage");

          yield {
            kind: "taxCode",
            taxCode: {
              code,
              description:
                childText(details, "Description") ??
                childText(node, "Description") ??
                code,
              type: options.taxCodeType ?? "sales",
              ...(percentage === undefined
                ? {}
                : {
                    rateBps: rateBpsOf(percentage, `TaxPercentage of ${code}`),
                  }),
            },
          };
        }
      } else if (event.path === TRANSACTION) {
        const first = journalRecord();

        if (first !== undefined) {
          yield first;
        }

        if (journal.code === undefined) {
          throw new AuditFileError(
            "AUDIT_FILE_INVALID",
            "a Transaction is outside a Journal with a JournalID",
          );
        }

        const id = requiredText(node, "TransactionID", "a Transaction");
        const description = childText(node, "Description");
        const lines: AuditEntry["lines"][number][] = [];
        let reference: string | undefined;

        for (const line of childrenOf(node, "Line")) {
          const where = `Transaction ${id}`;
          const debit = amountChild(line, "DebitAmount", decimals, where) ?? 0n;

          const credit =
            amountChild(line, "CreditAmount", decimals, where) ?? 0n;

          const net = sides(debit - credit, "debit");
          const tax = childNode(line, "TaxInformation");

          const taxCode =
            tax === undefined ? undefined : childText(tax, "TaxCode");

          const taxAmount =
            tax === undefined
              ? undefined
              : amountChild(tax, "TaxAmount", decimals, where);

          const party =
            childText(line, "CustomerID") ??
            childText(line, "SupplierID") ??
            childText(node, "CustomerID") ??
            childText(node, "SupplierID");

          const lineDescription = childText(line, "Description");

          reference ??= childText(line, "SourceDocumentID");

          debitTotal += net.debit;
          creditTotal += net.credit;
          lines.push({
            accountCode: requiredText(line, "AccountID", where),
            ...net,
            ...(lineDescription === undefined
              ? {}
              : { description: lineDescription }),
            ...(party === undefined ? {} : { partyCode: party }),
            ...(taxCode === undefined ? {} : { taxCode }),
            ...(taxAmount === undefined ? {} : { taxAmount }),
          });
        }

        yield {
          kind: "entry",
          entry: {
            journalCode: journal.code,
            id,
            date: parseDate(
              requiredText(node, "TransactionDate", `Transaction ${id}`),
              "TransactionDate",
            ),
            ...(description === undefined ? {} : { description }),
            ...(reference === undefined ? {} : { reference }),
            lines,
          },
        };
      }
    }
  }

  controlTotals(
    log,
    { debit: statedDebit, credit: statedCredit },
    { debit: debitTotal, credit: creditTotal },
  );
  yield* log.records();
}

const dateOnly = (date: string): string => date.slice(0, 10);

function exportBooks(
  options: SaftOptions,
  books: AuditBooks,
): Iterable<string> {
  const { header } = books;
  const created = options.createdOn ?? new Date().toISOString().slice(0, 10);

  const openings = new Map<string, bigint>();

  for (const balance of books.openingBalances) {
    openings.set(
      balance.accountCode,
      (openings.get(balance.accountCode) ?? 0n) + balance.amount,
    );
  }

  const amount = (value: bigint): string =>
    formatAmount(value < 0n ? -value : value, 2);

  const opening = (code: string): string => {
    const value = openings.get(code) ?? 0n;

    return value === 0n
      ? ""
      : tag(
          value > 0n ? "OpeningDebitBalance" : "OpeningCreditBalance",
          amount(value),
        );
  };

  const supplierCodes = new Set(
    books.parties
      .filter((entry) => entry.kind === "supplier")
      .map((entry) => entry.code),
  );

  const partyElement = (code: string | undefined): string =>
    code !== undefined && supplierCodes.has(code) ? "SupplierID" : "CustomerID";

  const accountXml = books.accounts.map((account) =>
    wrap("Account", [
      tag("AccountID", account.code),
      tag("AccountDescription", account.name),
      tag(
        "AccountType",
        account.type[0]?.toUpperCase() + account.type.slice(1),
      ),
      opening(account.code),
    ]),
  );

  const party = (kind: "customer" | "supplier"): string[] =>
    books.parties
      .filter((entry) => entry.kind === kind)
      .map((entry) =>
        wrap(kind === "customer" ? "Customer" : "Supplier", [
          tag(kind === "customer" ? "CustomerID" : "SupplierID", entry.code),
          tag("AccountID", entry.accountCode),
          tag(
            kind === "customer" ? "CustomerTaxID" : "SupplierTaxID",
            entry.taxId,
          ),
          tag("CompanyName", entry.name),
        ]),
      );

  const taxXml = wrap(
    "TaxTable",
    books.taxCodes.length === 0
      ? []
      : [
          wrap("TaxTableEntry", [
            tag("TaxType", "VAT"),
            tag("Description", "Value added tax"),
            ...books.taxCodes.map((code) =>
              wrap("TaxCodeDetails", [
                tag("TaxCode", code.code),
                tag("Description", code.description),
                tag(
                  "TaxPercentage",
                  code.rateBps === undefined
                    ? undefined
                    : formatAmount(BigInt(code.rateBps), 2),
                ),
              ]),
            ),
          ]),
        ],
  );

  const totalDebit = books.entries.reduce(
    (sum, entry) =>
      entry.lines.reduce((inner, line) => inner + line.debit, sum),
    0n,
  );

  const totalCredit = books.entries.reduce(
    (sum, entry) =>
      entry.lines.reduce((inner, line) => inner + line.credit, sum),
    0n,
  );

  const journalXml = books.journals.map((journal) => {
    const entries = books.entries.filter(
      (entry) => entry.journalCode === journal.code,
    );

    return wrap("Journal", [
      tag("JournalID", journal.code),
      tag("Description", journal.name),
      tag("Type", journal.type),
      ...entries.map((entry) =>
        wrap("Transaction", [
          tag("TransactionID", entry.id),
          tag("Period", String(Number(entry.date.slice(5, 7)))),
          tag("PeriodYear", entry.date.slice(0, 4)),
          tag("TransactionDate", entry.date),
          tag("Description", entry.description),
          ...entry.lines.map((line, index) =>
            wrap("Line", [
              tag("RecordID", String(index + 1)),
              tag("AccountID", line.accountCode),
              tag("Description", line.description),
              tag("SourceDocumentID", entry.reference),
              line.debit === 0n ? "" : tag("DebitAmount", amount(line.debit)),
              line.credit === 0n
                ? ""
                : tag("CreditAmount", amount(line.credit)),
              tag(partyElement(line.partyCode), line.partyCode),
              wrap("TaxInformation", [
                tag("TaxCode", line.taxCode),
                tag(
                  "TaxAmount",
                  line.taxAmount === undefined
                    ? undefined
                    : amount(line.taxAmount),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    ]);
  });

  return [
    `<?xml version="1.0" encoding="UTF-8"?>\n<AuditFile xmlns="${SAFT_NAMESPACE}">`,
    wrap("Header", [
      tag("AuditFileVersion", SPEC_PINS.saftOecd),
      tag("AuditFileCountry", header.company.country),
      tag("AuditFileDateCreated", created),
      tag("SoftwareCompanyName", header.software?.name),
      tag("SoftwareVersion", header.software?.version),
      wrap("Company", [
        tag("RegistrationNumber", header.company.registrationNumber),
        tag("Name", header.company.name),
      ]),
      tag("DefaultCurrencyCode", header.currency),
      wrap("SelectionCriteria", [
        tag("SelectionStartDate", dateOnly(header.startDate)),
        tag("SelectionEndDate", dateOnly(header.endDate)),
        tag("PeriodStartYear", String(header.fiscalYear)),
      ]),
      tag("TaxRegistrationNumber", header.company.taxId),
    ]),
    wrap("MasterFiles", [
      wrap("GeneralLedgerAccounts", accountXml),
      wrap("Customers", party("customer")),
      wrap("Suppliers", party("supplier")),
      taxXml,
    ]),
    wrap("GeneralLedgerEntries", [
      tag("NumberOfEntries", String(books.entries.length)),
      tag("TotalDebit", amount(totalDebit)),
      tag("TotalCredit", amount(totalCredit)),
      ...journalXml,
    ]),
    "</AuditFile>\n",
  ];
}

/**
 * The OECD SAF-T 2.00 adapter. It reads and writes the general ledger parts of
 * the file: header, accounts with opening balances, customers, suppliers, tax
 * codes and journals with transactions. Everything else is reported as an
 * unmapped element.
 */
export function saftAdapter(options: SaftOptions = {}): AuditFileAdapter {
  return defineAuditFileAdapter({
    apiVersion: 1,
    key: `saft-oecd-${SPEC_PINS.saftOecd}`,
    format: "SAF-T",
    version: SPEC_PINS.saftOecd,
    parse: (source, parseOptions) => parse(options, source, parseOptions),
    export: (books) => exportBooks(options, books),
  });
}
