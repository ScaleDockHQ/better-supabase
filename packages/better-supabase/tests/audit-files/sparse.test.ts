import { describe, expect, it } from "vitest";

import type {
  AuditFileAdapter,
  AuditRecord,
} from "../../src/audit-files/index.ts";

import { saftAdapter, xafAdapter } from "../../src/audit-files/index.ts";

async function collect(adapter: AuditFileAdapter, xml: string) {
  const records: AuditRecord[] = [];

  for await (const record of adapter.parse(xml)) {
    records.push(record);
  }

  return records;
}

const warningCodes = (records: readonly AuditRecord[]) =>
  records.flatMap((record) =>
    record.kind === "warning" ? [record.warning.code] : [],
  );

const SAFT = `<AuditFile xmlns="urn:OECD:StandardAuditFile-Taxation/2.00">
<Header>
  <SelectionCriteria><SelectionStartDate>2026-01-01T00:00:00</SelectionStartDate><SelectionEndDate>2026-12-31</SelectionEndDate></SelectionCriteria>
</Header>
<MasterFiles>
  <GeneralLedgerAccounts>
    <Account><AccountID>1</AccountID><AccountType>Mystery</AccountType><OpeningCreditBalance>5.00</OpeningCreditBalance></Account>
    <Account><AccountID>2</AccountID><AccountType>Liability</AccountType><OpeningDebitBalance>5.00</OpeningDebitBalance></Account>
  </GeneralLedgerAccounts>
  <Customers><Customer><CustomerID>C</CustomerID><AccountID>1</AccountID><OpeningDebitBalance>1.00</OpeningDebitBalance></Customer></Customers>
  <Suppliers><Supplier><SupplierID>S</SupplierID><Name>Vendor</Name></Supplier></Suppliers>
  <TaxTable><TaxTableEntry><Description>VAT</Description><TaxCodeDetails><TaxCode>X</TaxCode></TaxCodeDetails><TaxCodeDetails><TaxCode>Y</TaxCode><TaxPercentage>9</TaxPercentage><Description>Nine</Description></TaxCodeDetails></TaxTableEntry></TaxTable>
</MasterFiles>
<GeneralLedgerEntries>
  <NumberOfEntries>1</NumberOfEntries>
  <TotalDebit>3.00</TotalDebit>
  <TotalCredit>3.00</TotalCredit>
  <Journal>
    <JournalID>J</JournalID>
    <Type>Inkoop</Type>
    <Transaction>
      <TransactionID>T1</TransactionID>
      <TransactionDate>2026-03-01</TransactionDate>
      <SupplierID>S</SupplierID>
      <Line><AccountID>1</AccountID><DebitAmount><Amount>3.00</Amount></DebitAmount></Line>
      <Line><AccountID>2</AccountID><CreditAmount>3.00</CreditAmount><TaxInformation><TaxCode>Y</TaxCode><TaxAmount><Amount>0.25</Amount></TaxAmount></TaxInformation></Line>
    </Transaction>
  </Journal>
</GeneralLedgerEntries>
</AuditFile>`;

describe("a sparse SAF-T file", () => {
  it("fills what the file leaves out and warns about guesses", async () => {
    const records = await collect(
      saftAdapter({ taxCodeType: "purchase" }),
      SAFT,
    );

    const header = records.find((record) => record.kind === "header");

    expect(header?.kind === "header" && header.header).toMatchObject({
      fiscalYear: 2026,
      startDate: "2026-01-01",
      currency: "EUR",
      company: { name: "" },
    });
    expect(warningCodes(records)).toContain("AUDIT_ACCOUNT_TYPE_ASSUMED");

    const journal = records.find((record) => record.kind === "journal");

    expect(journal?.kind === "journal" && journal.journal.type).toBe(
      "purchase",
    );

    const taxCodes = records.flatMap((record) =>
      record.kind === "taxCode" ? [record.taxCode] : [],
    );

    expect(taxCodes).toEqual([
      expect.objectContaining({
        code: "X",
        description: "VAT",
        type: "purchase",
      }),
      expect.objectContaining({ code: "Y", description: "Nine", rateBps: 900 }),
    ]);

    const entry = records.find((record) => record.kind === "entry");

    expect(entry?.kind === "entry" && entry.entry.lines[0]).toMatchObject({
      debit: 300n,
      partyCode: "S",
    });
  });

  it("lets the app decide account and journal types", async () => {
    const records = await collect(
      saftAdapter({ accountType: () => "equity", journalType: () => "cash" }),
      SAFT,
    );

    expect(warningCodes(records)).not.toContain("AUDIT_ACCOUNT_TYPE_ASSUMED");
  });

  it("refuses an entry outside a journal and an unbalanced amount", async () => {
    await expect(
      collect(
        saftAdapter({}),
        SAFT.replace("<Journal>", "<Journal><Bad/>").replace(
          "2026-03-01",
          "soon",
        ),
      ),
    ).rejects.toMatchObject({ code: "AUDIT_FILE_INVALID" });
    await expect(
      collect(
        saftAdapter({}),
        SAFT.replace("3.00</CreditAmount>", "x</CreditAmount>"),
      ),
    ).rejects.toMatchObject({ code: "AUDIT_AMOUNT_INVALID" });
  });
});

const XAF = `<auditfile xmlns="http://www.auditfiles.nl/XAF/3.2">
<header><fiscalYear>2026</fiscalYear><startDate>2026-01-01</startDate><endDate>2026-12-31</endDate><curCode>EUR</curCode></header>
<company>
  <companyIdent>123</companyIdent>
  <companyName>Acme</companyName>
  <taxRegistrationCountry>NL</taxRegistrationCountry>
  <taxRegIdent>NL1B01</taxRegIdent>
  <customersSuppliers>
    <customerSupplier><custSupID>C1</custSupID><custSupName>Client</custSupName><custSupTp>C</custSupTp><taxRegIdent>NL9</taxRegIdent><country>NL</country></customerSupplier>
    <customerSupplier><custSupID>S1</custSupID><custSupName>Vendor</custSupName><custSupTp>S</custSupTp></customerSupplier>
    <customerSupplier><custSupID>B</custSupID><custSupName>Both</custSupName><custSupTp>B</custSupTp></customerSupplier>
  </customersSuppliers>
  <generalLedger>
    <ledgerAccount><accID>1</accID><accDesc>Cash</accDesc><accTp>B</accTp></ledgerAccount>
    <ledgerAccount><accID>2</accID><accTp>P</accTp></ledgerAccount>
    <ledgerAccount><accID>3</accID><accDesc>Mixed</accDesc></ledgerAccount>
  </generalLedger>
  <vatCodes><vatCode><vatID>H</vatID><vatDesc>High</vatDesc><vatToPay>1</vatToPay><vatToClaim>0</vatToClaim></vatCode></vatCodes>
  <openingBalance>
    <opBalDate>2026-01-01</opBalDate>
    <obLine><accID>1</accID><amnt>10.00</amnt><amntTp>D</amntTp></obLine>
    <obLine><accID>2</accID><amnt>10.00</amnt><amntTp>C</amntTp><custSupID>C1</custSupID></obLine>
  </openingBalance>
  <transactions>
    <linesCount>2</linesCount><totalDebit>5.00</totalDebit><totalCredit>5.00</totalCredit>
    <journal>
      <jrnID>BK</jrnID><desc>Bank</desc><jrnTp>B</jrnTp>
      <transaction>
        <nr>1</nr><desc>Pay</desc><periodNumber>2</periodNumber><trDt>2026-02-01</trDt>
        <trLine><nr>1</nr><accID>1</accID><docRef>D1</docRef><effDate>2026-02-01</effDate><desc>l</desc><amnt>5.00</amnt><amntTp>D</amntTp><custSupID>C1</custSupID></trLine>
        <trLine><nr>2</nr><accID>2</accID><amnt>5.00</amnt><amntTp>C</amntTp><vat><vatID>H</vatID><vatAmnt>0.87</vatAmnt><vatAmntTp>C</vatAmntTp></vat></trLine>
      </transaction>
    </journal>
  </transactions>
</company>
</auditfile>`;

describe("a sparse XAF file", () => {
  it("reads parties, vat codes and types, and warns about assumptions", async () => {
    const records = await collect(xafAdapter({}), XAF);
    const kinds = new Set(records.map((record) => record.kind));

    for (const kind of [
      "header",
      "account",
      "party",
      "taxCode",
      "journal",
      "entry",
    ]) {
      expect(kinds.has(kind as AuditRecord["kind"])).toBe(true);
    }

    expect(warningCodes(records)).toContain("AUDIT_ACCOUNT_TYPE_ASSUMED");
  });

  it("refuses an account type it does not know", async () => {
    await expect(
      collect(
        xafAdapter({}),
        XAF.replace("<accTp>B</accTp>", "<accTp>Q</accTp>"),
      ),
    ).rejects.toMatchObject({ code: "AUDIT_FILE_INVALID" });
  });
});
