import { describe, expect, it } from "vitest";

import {
  creditorReference,
  isIban,
  parseCamt053,
  parseMt940,
  referencePayload,
} from "../../../src/blocks/banking/index.ts";
import { money } from "../../../src/commerce/money.ts";

const CAMT_02 = `<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">
  <BkToCstmrStmt>
    <GrpHdr><MsgId>MSG-1</MsgId><CreDtTm>2026-10-02T06:00:00</CreDtTm></GrpHdr>
    <Stmt>
      <Id>STMT-2026-275</Id>
      <FrToDt><FrDtTm>2026-10-01T00:00:00</FrDtTm><ToDtTm>2026-10-01T23:59:59</ToDtTm></FrToDt>
      <Acct><Id><IBAN>NL91ABNA0417164300</IBAN></Id><Ccy>EUR</Ccy></Acct>
      <Bal>
        <Tp><CdOrPrtry><Cd>OPBD</Cd></CdOrPrtry></Tp>
        <Amt Ccy="EUR">1000.00</Amt><CdtDbtInd>CRDT</CdtDbtInd>
        <Dt><Dt>2026-10-01</Dt></Dt>
      </Bal>
      <Bal>
        <Tp><CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp>
        <Amt Ccy="EUR">1171.45</Amt><CdtDbtInd>CRDT</CdtDbtInd>
        <Dt><Dt>2026-10-01</Dt></Dt>
      </Bal>
      <Ntry>
        <NtryRef>1</NtryRef>
        <Amt Ccy="EUR">242.00</Amt><CdtDbtInd>CRDT</CdtDbtInd>
        <Sts>BOOK</Sts>
        <BookgDt><Dt>2026-10-01</Dt></BookgDt><ValDt><Dt>2026-10-01</Dt></ValDt>
        <AcctSvcrRef>BANK-0001</AcctSvcrRef>
        <NtryDtls><TxDtls>
          <Refs><EndToEndId>E2E-42</EndToEndId></Refs>
          <RltdPties>
            <Dbtr><Nm>Acme B.V.</Nm></Dbtr>
            <DbtrAcct><Id><IBAN>NL02 RABO 0123 4567 89</IBAN></Id></DbtrAcct>
          </RltdPties>
          <RmtInf><Strd><CdtrRefInf><Ref>RF73INV20260042</Ref></CdtrRefInf></Strd></RmtInf>
        </TxDtls></NtryDtls>
      </Ntry>
      <Ntry>
        <Amt Ccy="EUR">70.55</Amt><CdtDbtInd>DBIT</CdtDbtInd>
        <Sts>BOOK</Sts>
        <BookgDt><Dt>2026-10-01</Dt></BookgDt>
        <AcctSvcrRef>BANK-0002</AcctSvcrRef>
        <NtryDtls><TxDtls>
          <RltdPties><Cdtr><Nm>Energy &amp; Co</Nm></Cdtr></RltdPties>
          <RmtInf><Ustrd>Invoice 2026-118</Ustrd><Ustrd>October</Ustrd></RmtInf>
        </TxDtls></NtryDtls>
      </Ntry>
      <Ntry>
        <Amt Ccy="EUR">5.00</Amt><CdtDbtInd>DBIT</CdtDbtInd>
        <Sts>PDNG</Sts>
        <BookgDt><Dt>2026-10-01</Dt></BookgDt>
      </Ntry>
    </Stmt>
  </BkToCstmrStmt>
</Document>`;

const CAMT_08 = `<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08">
  <BkToCstmrStmt>
    <Stmt>
      <Id>S8</Id>
      <Acct><Id><Othr><Id>123456</Id></Othr></Id><Ccy>EUR</Ccy></Acct>
      <Bal>
        <Tp><CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp>
        <Amt Ccy="EUR">10.00</Amt><CdtDbtInd>DBIT</CdtDbtInd>
        <Dt><Dt>2026-10-03</Dt></Dt>
      </Bal>
      <Ntry>
        <Amt Ccy="EUR">300.00</Amt><CdtDbtInd>CRDT</CdtDbtInd>
        <Sts><Cd>BOOK</Cd></Sts>
        <BookgDt><DtTm>2026-10-03T09:30:00+02:00</DtTm></BookgDt>
        <AcctSvcrRef>BATCH-9</AcctSvcrRef>
        <NtryDtls>
          <TxDtls>
            <Refs><TxId>T1</TxId></Refs>
            <Amt Ccy="EUR">100.00</Amt>
            <RltdPties><Dbtr><Pty><Nm>First</Nm></Pty></Dbtr></RltdPties>
          </TxDtls>
          <TxDtls>
            <Amt Ccy="EUR">200.00</Amt>
            <RltdPties><Dbtr><Pty><Nm>Second</Nm></Pty></Dbtr></RltdPties>
          </TxDtls>
        </NtryDtls>
      </Ntry>
      <Ntry>
        <Amt Ccy="EUR">20.00</Amt><CdtDbtInd>CRDT</CdtDbtInd>
        <RvslInd>true</RvslInd>
        <Sts><Cd>BOOK</Cd></Sts>
        <BookgDt><Dt>2026-10-03</Dt></BookgDt>
      </Ntry>
    </Stmt>
  </BkToCstmrStmt>
</Document>`;

const MT940 = `{1:F01ABNANL2AXXXX0000000000}{2:I940ABNANL2AXXXXN}{4:
:20:ABN-275
:25:NL91ABNA0417164300EUR
:28C:00275/1
:60F:C261001EUR1000,00
:61:2610011001C242,00NTRFNONREF//BANK-0001
:86:/TRTP/SEPA OVERBOEKING/IBAN/NL02RABO0123456789/BIC/RABONL2U/NAME/A
cme B.V./REMI/STRD/CUR/1234567890123456/EREF/E2E-42
:61:261001D70,55NDDTNONREF
:86:/TRTP/SEPA Incasso/CSID/NL99ZZZ/NAME/Energy Co/REMI/USTD//Invoice 2
026-118/EREF/NOTPROVIDED
:61:261001C12,00NTRFREF-3
:86:166?00GUTSCHRIFT?20EREF+DE-1?21SVWZ+Rechnung 77?31DE89370400440532
013000?32Muster GmbH
:62F:C261001EUR1183,45
-}`;

describe("parseCamt053", () => {
  it("reads a camt.053.001.02 statement with its booked entries", async () => {
    const [statement] = await parseCamt053(CAMT_02);

    expect(statement).toEqual({
      format: "camt053",
      account: { iban: "NL91ABNA0417164300", currency: "EUR" },
      reference: "STMT-2026-275",
      fromOn: "2026-10-01",
      untilOn: "2026-10-01",
      openingBalance: money(100_000n, "EUR"),
      closingBalance: money(117_145n, "EUR"),
      transactions: [
        {
          bookedOn: "2026-10-01",
          valueOn: "2026-10-01",
          amount: money(24_200n, "EUR"),
          externalId: "BANK-0001",
          counterpartyName: "Acme B.V.",
          counterpartyIban: "NL02RABO0123456789",
          structuredReference: "RF73INV20260042",
          endToEndId: "E2E-42",
        },
        {
          bookedOn: "2026-10-01",
          amount: money(-7055n, "EUR"),
          externalId: "BANK-0002",
          counterpartyName: "Energy & Co",
          remittance: "Invoice 2026-118 October",
        },
      ],
    });
  });

  it("reads camt.053.001.08: Sts codes, Pty names, batches and reversals", async () => {
    const [statement] = await parseCamt053(CAMT_08);

    expect(statement?.account).toEqual({
      identification: "123456",
      currency: "EUR",
    });
    expect(statement?.closingBalance).toEqual(money(-1000n, "EUR"));
    expect(statement?.transactions).toEqual([
      {
        bookedOn: "2026-10-03",
        amount: money(10_000n, "EUR"),
        externalId: "T1",
        counterpartyName: "First",
      },
      {
        bookedOn: "2026-10-03",
        amount: money(20_000n, "EUR"),
        externalId: "BATCH-9/2",
        counterpartyName: "Second",
      },
      { bookedOn: "2026-10-03", amount: money(-2000n, "EUR") },
    ]);
  });

  it("refuses a document that isn't a camt.053 statement", async () => {
    await expect(parseCamt053("<Document/>")).rejects.toThrow(TypeError);
    await expect(
      parseCamt053(
        '<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02"><BkToCstmrStmt/></Document>',
      ),
    ).rejects.toThrow("at least one");
  });
});

describe("parseMt940", () => {
  it("reads balances, signed entries and the :86: layouts", () => {
    const [statement] = parseMt940(MT940);

    expect(statement).toEqual({
      format: "mt940",
      account: { iban: "NL91ABNA0417164300", currency: "EUR" },
      reference: "ABN-275/00275/1",
      fromOn: "2026-10-01",
      untilOn: "2026-10-01",
      openingBalance: money(100_000n, "EUR"),
      closingBalance: money(118_345n, "EUR"),
      transactions: [
        {
          bookedOn: "2026-10-01",
          valueOn: "2026-10-01",
          amount: money(24_200n, "EUR"),
          externalId: "BANK-0001",
          counterpartyIban: "NL02RABO0123456789",
          counterpartyName: "Acme B.V.",
          structuredReference: "1234567890123456",
          endToEndId: "E2E-42",
        },
        {
          bookedOn: "2026-10-01",
          valueOn: "2026-10-01",
          amount: money(-7055n, "EUR"),
          counterpartyName: "Energy Co",
          remittance: "Invoice 2026-118",
        },
        {
          bookedOn: "2026-10-01",
          valueOn: "2026-10-01",
          amount: money(1200n, "EUR"),
          externalId: "REF-3",
          counterpartyIban: "DE89370400440532013000",
          counterpartyName: "Muster GmbH",
          remittance: "Rechnung 77",
          endToEndId: "DE-1",
        },
      ],
    });
  });

  it("reads several statements and a debit balance", () => {
    const statements = parseMt940(
      ":20:A\n:25:12345\n:60F:D261001EUR5,\n:62F:D261001EUR5,\n:20:B\n:25:12345\n:60M:C261002USD1,5\n",
    );

    expect(
      statements.map((s) => [s.reference, s.account, s.openingBalance]),
    ).toEqual([
      ["A", { identification: "12345", currency: "EUR" }, money(-500n, "EUR")],
      ["B", { identification: "12345", currency: "USD" }, money(150n, "USD")],
    ]);
  });

  it("refuses text without a statement or a balance", () => {
    expect(() => parseMt940("hello")).toThrow("No MT940 statement");
    expect(() => parseMt940(":20:A\n:25:1\n")).toThrow(":60F:");
    expect(() => parseMt940(":20:A\n:60F:C261001EUR1,\n:61:nope\n")).toThrow(
      ":61:",
    );
  });
});

describe("payment references", () => {
  it("makes and checks ISO 11649 references", () => {
    expect(creditorReference("INV-2026-0042")).toBe("RF73INV20260042");
    expect(referencePayload("RF18 5390 0754 7034")).toBe("539007547034");
    expect(referencePayload("RF19539007547034")).toBeUndefined();
    expect(() => creditorReference("")).toThrow(RangeError);
  });

  it("checks a Dutch betalingskenmerk", () => {
    expect(referencePayload("6000.0000.2026.0042")).toBe("20260042");
    expect(referencePayload("7000000020260042")).toBeUndefined();
    expect(referencePayload("hello")).toBeUndefined();
  });

  it("checks IBANs", () => {
    expect(isIban("NL91 ABNA 0417 1643 00")).toBe(true);
    expect(isIban("NL92ABNA0417164300")).toBe(false);
  });
});
