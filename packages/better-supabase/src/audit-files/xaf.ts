import type {
  AuditAccountType,
  AuditBooks,
  AuditEntry,
  AuditFileAdapter,
  AuditFileSource,
  AuditHeader,
  AuditJournalType,
  AuditParseOptions,
  AuditRecord,
} from "./model.ts";
import type { WalkSpec, XmlNode } from "./xml.ts";

import { SPEC_PINS } from "../core/spec-pins.ts";
import { AuditFileError, defineAuditFileAdapter } from "./model.ts";
import {
  controlTotals,
  formatAmount,
  monthsBetween,
  parseAmount,
  parseDate,
  requiredText,
  sides,
  WarningLog,
} from "./support.ts";
import { childNode, childrenOf, childText, tag, walk, wrap } from "./xml.ts";

/** The namespace of the Dutch audit file 3.2 schema. */
export const XAF_NAMESPACE = "http://www.auditfiles.nl/XAF/3.2";

export interface XafOptions {
  /**
   * The type of a ledger account. An XAF file only says balance (`B`), profit
   * and loss (`P`) or mixed (`M`), so a balance account is an asset and a
   * profit and loss account an expense unless this says otherwise.
   */
  readonly accountType?: (account: {
    readonly code: string;
    readonly name: string;
    readonly kind: "balance" | "profit_loss" | "mixed";
  }) => AuditAccountType | undefined;
  /** Maps `jrnTp`. Default: by code or keyword, else `general`. */
  readonly journalType?: (raw: string | undefined) => AuditJournalType;
  /** The type of a VAT code; default `sales`. */
  readonly taxCodeType?: "sales" | "purchase";
  /** `dateCreated` of an export, `YYYY-MM-DD`; default today. */
  readonly createdOn?: string;
}

const ROOT = "auditfile";
const COMPANY = `${ROOT}/company`;
const LEDGER_ACCOUNT = `${COMPANY}/generalLedger/ledgerAccount`;
const PARTY = `${COMPANY}/customersSuppliers/customerSupplier`;
const VAT = `${COMPANY}/vatCodes/vatCode`;
const PERIOD = `${COMPANY}/periods/period`;
const OPENING = `${COMPANY}/openingBalance`;
const TRANSACTIONS = `${COMPANY}/transactions`;
const JOURNAL = `${TRANSACTIONS}/journal`;
const TRANSACTION = `${JOURNAL}/transaction`;

const set = (...paths: string[]): ReadonlySet<string> => new Set(paths);

const SPEC: WalkSpec = {
  records: new Map<string, ReadonlySet<string>>([
    [
      `${ROOT}/header`,
      set(
        "fiscalYear",
        "startDate",
        "endDate",
        "curCode",
        "dateCreated",
        "softwareDesc",
        "softwareVersion",
      ),
    ],
    [LEDGER_ACCOUNT, set("accID", "accDesc", "accTp")],
    [
      PARTY,
      set(
        "custSupID",
        "custSupName",
        "custSupTp",
        "taxRegistrationCountry",
        "taxRegIdent",
      ),
    ],
    [VAT, set("vatID", "vatDesc", "vatToPayAccID", "vatToClaimAccID")],
    [
      PERIOD,
      set("periodNumber", "periodDesc", "startDatePeriod", "endDatePeriod"),
    ],
    [
      OPENING,
      set(
        "opBalDate",
        "opBalDesc",
        "linesCount",
        "totalDebit",
        "totalCredit",
        "obLine",
        "obLine/nr",
        "obLine/accID",
        "obLine/amnt",
        "obLine/amntTp",
        "obLine/custSupID",
      ),
    ],
    [
      TRANSACTION,
      set(
        "nr",
        "desc",
        "periodNumber",
        "trDt",
        "amnt",
        "amntTp",
        "trLine",
        "trLine/nr",
        "trLine/accID",
        "trLine/docRef",
        "trLine/effDate",
        "trLine/desc",
        "trLine/amnt",
        "trLine/amntTp",
        "trLine/custSupID",
        "trLine/vat",
        "trLine/vat/vatID",
        "trLine/vat/vatAmnt",
        "trLine/vat/vatAmntTp",
      ),
    ],
  ]),
  containers: set(
    ROOT,
    COMPANY,
    `${COMPANY}/generalLedger`,
    `${COMPANY}/customersSuppliers`,
    `${COMPANY}/vatCodes`,
    `${COMPANY}/periods`,
    TRANSACTIONS,
    JOURNAL,
  ),
  leaves: set(
    `${COMPANY}/companyIdent`,
    `${COMPANY}/companyName`,
    `${COMPANY}/taxRegistrationCountry`,
    `${COMPANY}/taxRegIdent`,
    `${TRANSACTIONS}/linesCount`,
    `${TRANSACTIONS}/totalDebit`,
    `${TRANSACTIONS}/totalCredit`,
    `${JOURNAL}/jrnID`,
    `${JOURNAL}/desc`,
    `${JOURNAL}/jrnTp`,
  ),
};

const BANK = /^b$|bank|giro/iu;
const CASH = /^[ck]$|cash|kas/iu;
const SELLING = /^[vs]$|sale|verkoop/iu;
const BUYING = /^[ip]$|purchase|inkoop/iu;

function journalTypeOf(raw: string | undefined): AuditJournalType {
  const text = raw?.trim();

  if (text === undefined || text === "") {
    return "general";
  }

  if (BANK.test(text)) {
    return "bank";
  }

  if (CASH.test(text)) {
    return "cash";
  }

  if (SELLING.test(text)) {
    return "sales";
  }

  if (BUYING.test(text)) {
    return "purchase";
  }

  return "general";
}

const KIND: Readonly<
  Record<string, "balance" | "mixed" | "profit_loss" | undefined>
> = { B: "balance", P: "profit_loss", M: "mixed" };

function amountOf(
  node: XmlNode,
  amountName: string,
  sideName: string,
  decimals: number | undefined,
  where: string,
): { readonly debit: bigint; readonly credit: bigint } {
  const text = requiredText(node, amountName, where);
  const side = requiredText(node, sideName, where).toUpperCase();

  if (side !== "D" && side !== "C") {
    throw new AuditFileError(
      "AUDIT_FILE_INVALID",
      `${where}: ${sideName} is "${side}", not D or C`,
    );
  }

  return sides(
    parseAmount(text, decimals, where),
    side === "D" ? "debit" : "credit",
  );
}

async function* parse(
  options: XafOptions,
  source: AuditFileSource,
  parseOptions: AuditParseOptions = {},
): AsyncGenerator<AuditRecord> {
  const decimals = parseOptions.decimals;
  const log = new WarningLog();
  let header: AuditHeader | undefined;
  let headerNode: XmlNode | undefined;
  let headerSent = false;

  const company: {
    name?: string;
    ident?: string;
    country?: string;
    taxId?: string;
  } = {};

  let journal: { code?: string; name?: string; type?: string; sent: boolean } =
    { sent: false };

  let debitTotal = 0n;
  let creditTotal = 0n;
  let statedDebit: bigint | undefined;
  let statedCredit: bigint | undefined;

  const buildHeader = (node: XmlNode): AuditHeader => {
    const start = parseDate(
      requiredText(node, "startDate", "the header"),
      "startDate",
    );

    const end = parseDate(
      requiredText(node, "endDate", "the header"),
      "endDate",
    );

    const stated = childText(node, "fiscalYear");
    const name = childText(node, "softwareDesc");
    const version = childText(node, "softwareVersion");

    return {
      fiscalYear:
        stated === undefined ? Number(start.slice(0, 4)) : Number(stated),
      startDate: start,
      endDate: end,
      currency: childText(node, "curCode") ?? "EUR",
      company: {
        name: company.name ?? "",
        ...(company.ident === undefined
          ? {}
          : { registrationNumber: company.ident }),
        ...(company.taxId === undefined ? {} : { taxId: company.taxId }),
        ...(company.country === undefined ? {} : { country: company.country }),
      },
      ...(name === undefined && version === undefined
        ? {}
        : {
            software: {
              ...(name === undefined ? {} : { name }),
              ...(version === undefined ? {} : { version }),
            },
          }),
    };
  };

  // The company's name follows the header in the file, so the header record
  // waits for the first record that needs it.
  const ensureHeader = (): AuditRecord | undefined => {
    if (headerSent) {
      return undefined;
    }

    if (headerNode === undefined) {
      throw new AuditFileError("AUDIT_FILE_INVALID", "the file has no header");
    }

    headerSent = true;
    header = buildHeader(headerNode);

    return { kind: "header", header };
  };

  const year = (): number => header?.fiscalYear ?? 0;

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

      continue;
    }

    if (event.type === "open" && event.path === JOURNAL) {
      journal = { sent: false };

      continue;
    }

    if (event.type === "close" && event.path === JOURNAL) {
      const record = journalRecord();

      if (record !== undefined) {
        yield record;
      }

      continue;
    }

    if (event.type === "leaf") {
      const name = event.path.slice(event.path.lastIndexOf("/") + 1);

      if (
        event.path.startsWith(`${COMPANY}/`) &&
        !event.path.startsWith(TRANSACTIONS)
      ) {
        if (name === "companyName") {
          company.name = event.text;
        } else if (name === "companyIdent") {
          company.ident = event.text;
        } else if (name === "taxRegistrationCountry") {
          company.country = event.text;
        } else if (name === "taxRegIdent") {
          company.taxId = event.text;
        }
      } else if (event.path === `${JOURNAL}/jrnID`) {
        journal.code = event.text;
      } else if (event.path === `${JOURNAL}/desc`) {
        journal.name = event.text;
      } else if (event.path === `${JOURNAL}/jrnTp`) {
        journal.type = event.text;
      } else if (
        event.path === `${TRANSACTIONS}/totalDebit` &&
        event.text !== ""
      ) {
        statedDebit = parseAmount(event.text, decimals, "totalDebit");
      } else if (
        event.path === `${TRANSACTIONS}/totalCredit` &&
        event.text !== ""
      ) {
        statedCredit = parseAmount(event.text, decimals, "totalCredit");
      }

      continue;
    }

    if (event.type !== "node") {
      continue;
    }

    const { node } = event;

    if (event.path === `${ROOT}/header`) {
      headerNode = node;

      continue;
    }

    const first = ensureHeader();

    if (first !== undefined) {
      yield first;
    }

    if (event.path === LEDGER_ACCOUNT) {
      const code = requiredText(node, "accID", "a ledgerAccount");
      const name = childText(node, "accDesc") ?? code;
      const raw = (childText(node, "accTp") ?? "M").toUpperCase();
      const kind = KIND[raw];

      if (kind === undefined) {
        throw new AuditFileError(
          "AUDIT_FILE_INVALID",
          `account ${code}: accTp is "${raw}", not B, P or M`,
        );
      }

      const mapped = options.accountType?.({ code, name, kind });

      if (mapped === undefined) {
        log.add(
          "AUDIT_ACCOUNT_TYPE_ASSUMED",
          "XAF does not tell assets from liabilities or income from expenses; balance accounts were imported as assets and profit and loss accounts as expenses (pass accountType to decide)",
        );
      }

      yield {
        kind: "account",
        account: {
          code,
          name,
          type: mapped ?? (kind === "profit_loss" ? "expense" : "asset"),
          ...(mapped === undefined ? { typeAssumed: true } : {}),
        },
      };
    } else if (event.path === PARTY) {
      const code = requiredText(node, "custSupID", "a customerSupplier");
      const type = (childText(node, "custSupTp") ?? "C").toUpperCase();
      const country = childText(node, "taxRegistrationCountry");
      const taxId = childText(node, "taxRegIdent");

      yield {
        kind: "party",
        party: {
          kind: type === "S" ? "supplier" : "customer",
          code,
          name: childText(node, "custSupName") ?? code,
          ...(taxId === undefined ? {} : { taxId }),
          ...(country === undefined ? {} : { country }),
        },
      };
    } else if (event.path === VAT) {
      const code = requiredText(node, "vatID", "a vatCode");

      yield {
        kind: "taxCode",
        taxCode: {
          code,
          description: childText(node, "vatDesc") ?? code,
          type: options.taxCodeType ?? "sales",
        },
      };
    } else if (event.path === OPENING) {
      for (const line of childrenOf(node, "obLine")) {
        const where = `opening balance line ${childText(line, "nr") ?? ""}`;

        const { debit, credit } = amountOf(
          line,
          "amnt",
          "amntTp",
          decimals,
          where,
        );

        const party = childText(line, "custSupID");

        yield {
          kind: "openingBalance",
          balance: {
            fiscalYear: year(),
            accountCode: requiredText(line, "accID", where),
            ...(party === undefined ? {} : { partyCode: party }),
            amount: debit - credit,
          },
        };
      }
    } else if (event.path === TRANSACTION) {
      const opened = journalRecord();

      if (opened !== undefined) {
        yield opened;
      }

      if (journal.code === undefined) {
        throw new AuditFileError(
          "AUDIT_FILE_INVALID",
          "a transaction is outside a journal with a jrnID",
        );
      }

      const id = requiredText(node, "nr", "a transaction");
      const where = `transaction ${id}`;
      const description = childText(node, "desc");
      const lines: AuditEntry["lines"][number][] = [];
      let reference: string | undefined;

      for (const line of childrenOf(node, "trLine")) {
        const { debit, credit } = amountOf(
          line,
          "amnt",
          "amntTp",
          decimals,
          where,
        );

        const party = childText(line, "custSupID");
        const lineDescription = childText(line, "desc");
        const vat = childNode(line, "vat");
        const taxCode = vat === undefined ? undefined : childText(vat, "vatID");

        const vatAmount =
          vat === undefined
            ? undefined
            : amountOf(vat, "vatAmnt", "vatAmntTp", decimals, where);

        reference ??= childText(line, "docRef");
        debitTotal += debit;
        creditTotal += credit;
        lines.push({
          accountCode: requiredText(line, "accID", where),
          debit,
          credit,
          ...(lineDescription === undefined
            ? {}
            : { description: lineDescription }),
          ...(party === undefined ? {} : { partyCode: party }),
          ...(taxCode === undefined ? {} : { taxCode }),
          ...(vatAmount === undefined
            ? {}
            : { taxAmount: vatAmount.debit - vatAmount.credit }),
        });
      }

      yield {
        kind: "entry",
        entry: {
          journalCode: journal.code,
          id,
          date: parseDate(requiredText(node, "trDt", where), "trDt"),
          ...(description === undefined ? {} : { description }),
          ...(reference === undefined ? {} : { reference }),
          lines,
        },
      };
    }
  }

  const last = ensureHeader();

  if (last !== undefined) {
    yield last;
  }

  controlTotals(
    log,
    { debit: statedDebit, credit: statedCredit },
    { debit: debitTotal, credit: creditTotal },
  );
  yield* log.records();
}

const JOURNAL_CODES: Readonly<Record<AuditJournalType, string>> = {
  sales: "V",
  purchase: "I",
  bank: "B",
  cash: "K",
  general: "M",
};

function exportBooks(options: XafOptions, books: AuditBooks): Iterable<string> {
  const { header } = books;
  const created = options.createdOn ?? new Date().toISOString().slice(0, 10);

  const amount = (value: bigint): string =>
    formatAmount(value < 0n ? -value : value, 2);

  const side = (value: bigint): string => (value < 0n ? "C" : "D");

  const parties = books.parties.map((party) =>
    wrap("customerSupplier", [
      tag("custSupID", party.code),
      tag("custSupName", party.name),
      tag("custSupTp", party.kind === "customer" ? "C" : "S"),
      tag("taxRegistrationCountry", party.country),
      tag("taxRegIdent", party.taxId),
    ]),
  );

  const accounts = books.accounts.map((account) =>
    wrap("ledgerAccount", [
      tag("accID", account.code),
      tag("accDesc", account.name),
      tag(
        "accTp",
        account.type === "income" || account.type === "expense" ? "P" : "B",
      ),
    ]),
  );

  const vat = books.taxCodes.map((code) =>
    wrap("vatCode", [
      tag("vatID", code.code),
      tag("vatDesc", code.description),
    ]),
  );

  const periods = monthsBetween(header.startDate, header.endDate).map(
    ([number, from, to]) =>
      wrap("period", [
        tag("periodNumber", String(number)),
        tag("periodDesc", from.slice(0, 7)),
        tag("startDatePeriod", from),
        tag("endDatePeriod", to),
      ]),
  );

  const openingDebit = books.openingBalances.reduce(
    (sum, row) => (row.amount > 0n ? sum + row.amount : sum),
    0n,
  );

  const openingCredit = books.openingBalances.reduce(
    (sum, row) => (row.amount < 0n ? sum - row.amount : sum),
    0n,
  );

  const opening =
    books.openingBalances.length === 0
      ? ""
      : wrap("openingBalance", [
          tag("opBalDate", header.startDate),
          tag("opBalDesc", "Opening balance"),
          tag("linesCount", String(books.openingBalances.length)),
          tag("totalDebit", amount(openingDebit)),
          tag("totalCredit", amount(openingCredit)),
          ...books.openingBalances.map((row, index) =>
            wrap("obLine", [
              tag("nr", String(index + 1)),
              tag("accID", row.accountCode),
              tag("amnt", amount(row.amount)),
              tag("amntTp", side(row.amount)),
              tag("custSupID", row.partyCode),
            ]),
          ),
        ]);

  let lineCount = 0;
  let totalDebit = 0n;
  let totalCredit = 0n;

  for (const entry of books.entries) {
    for (const line of entry.lines) {
      lineCount += 1;
      totalDebit += line.debit;
      totalCredit += line.credit;
    }
  }

  const journals = books.journals.map((journal) =>
    wrap("journal", [
      tag("jrnID", journal.code),
      tag("desc", journal.name),
      tag("jrnTp", JOURNAL_CODES[journal.type]),
      ...books.entries
        .filter((entry) => entry.journalCode === journal.code)
        .map((entry) => {
          const debit = entry.lines.reduce((sum, line) => sum + line.debit, 0n);

          return wrap("transaction", [
            tag("nr", entry.id),
            tag("desc", entry.description),
            tag("periodNumber", String(Number(entry.date.slice(5, 7)))),
            tag("trDt", entry.date),
            tag("amnt", amount(debit)),
            tag("amntTp", "D"),
            ...entry.lines.map((line, index) => {
              const net = line.debit - line.credit;

              return wrap("trLine", [
                tag("nr", String(index + 1)),
                tag("accID", line.accountCode),
                tag("docRef", entry.reference),
                tag("effDate", entry.date),
                tag("desc", line.description),
                tag("amnt", amount(net)),
                tag("amntTp", side(net)),
                tag("custSupID", line.partyCode),
                line.taxCode === undefined && line.taxAmount === undefined
                  ? ""
                  : wrap("vat", [
                      tag("vatID", line.taxCode),
                      tag(
                        "vatAmnt",
                        line.taxAmount === undefined
                          ? undefined
                          : amount(line.taxAmount),
                      ),
                      tag(
                        "vatAmntTp",
                        line.taxAmount === undefined
                          ? undefined
                          : side(line.taxAmount),
                      ),
                    ]),
              ]);
            }),
          ]);
        }),
    ]),
  );

  return [
    `<?xml version="1.0" encoding="UTF-8"?>\n<auditfile xmlns="${XAF_NAMESPACE}">`,
    wrap("header", [
      tag("fiscalYear", String(header.fiscalYear)),
      tag("startDate", header.startDate),
      tag("endDate", header.endDate),
      tag("curCode", header.currency),
      tag("dateCreated", created),
      tag("softwareDesc", header.software?.name ?? "better-supabase"),
      tag("softwareVersion", header.software?.version ?? SPEC_PINS.xaf),
    ]),
    wrap("company", [
      tag("companyIdent", header.company.registrationNumber),
      tag("companyName", header.company.name),
      tag("taxRegistrationCountry", header.company.country),
      tag("taxRegIdent", header.company.taxId),
      wrap("customersSuppliers", parties),
      wrap("generalLedger", accounts),
      wrap("vatCodes", vat),
      wrap("periods", periods),
      opening,
      wrap("transactions", [
        tag("linesCount", String(lineCount)),
        tag("totalDebit", amount(totalDebit)),
        tag("totalCredit", amount(totalCredit)),
        ...journals,
      ]),
    ]),
    "</auditfile>\n",
  ];
}

/**
 * The Dutch audit file (XAF) 3.2 adapter. It reads and writes the header,
 * ledger accounts, customers and suppliers, VAT codes, the opening balance and
 * the journals with transactions. Everything else is reported as an unmapped
 * element.
 */
export function xafAdapter(options: XafOptions = {}): AuditFileAdapter {
  return defineAuditFileAdapter({
    apiVersion: 1,
    key: `xaf-${SPEC_PINS.xaf}`,
    format: "XAF",
    version: SPEC_PINS.xaf,
    parse: (source, parseOptions) => parse(options, source, parseOptions),
    export: (books) => exportBooks(options, books),
  });
}
