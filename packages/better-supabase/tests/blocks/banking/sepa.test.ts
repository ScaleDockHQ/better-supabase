import { XMLParser } from "fast-xml-parser";
import { Temporal } from "temporal-polyfill";
import { describe, expect, it } from "vitest";

import type { SepaCreditTransferFile } from "../../../src/blocks/banking/index.ts";

import { sepaCreditTransferXml } from "../../../src/blocks/banking/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { SPEC_PINS } from "../../../src/core/spec-pins.ts";

const FILE: SepaCreditTransferFile = {
  messageId: "BATCH-2026-10-31",
  createdAt: Temporal.Instant.from("2026-10-31T09:30:00Z"),
  executionOn: Temporal.PlainDate.from("2026-11-02"),
  debtorName: "Acme B.V.",
  debtorIban: "NL91 ABNA 0417 1643 00",
  debtorBic: "ABNANL2A",
  transfers: [
    {
      endToEndId: "INV-1001",
      amount: money(118_000n, "EUR"),
      creditorName: "Müller & Söhne GmbH",
      creditorIban: "DE89370400440532013000",
      creditorBic: "COBADEFFXXX",
      remittance: "Invoice 1001",
    },
    {
      endToEndId: "INV-1002",
      amount: money(5050n, "EUR"),
      creditorName: "Bakker",
      creditorIban: "NL02ABNA0123456789",
    },
  ],
};

const GOLDEN = `<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.09" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><CstmrCdtTrfInitn><GrpHdr><MsgId>BATCH-2026-10-31</MsgId><CreDtTm>2026-10-31T09:30:00</CreDtTm><NbOfTxs>2</NbOfTxs><CtrlSum>1230.50</CtrlSum><InitgPty><Nm>Acme B.V.</Nm></InitgPty></GrpHdr><PmtInf><PmtInfId>BATCH-2026-10-31</PmtInfId><PmtMtd>TRF</PmtMtd><BtchBookg>true</BtchBookg><NbOfTxs>2</NbOfTxs><CtrlSum>1230.50</CtrlSum><PmtTpInf><SvcLvl><Cd>SEPA</Cd></SvcLvl></PmtTpInf><ReqdExctnDt><Dt>2026-11-02</Dt></ReqdExctnDt><Dbtr><Nm>Acme B.V.</Nm></Dbtr><DbtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></DbtrAcct><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt><ChrgBr>SLEV</ChrgBr><CdtTrfTxInf><PmtId><EndToEndId>INV-1001</EndToEndId></PmtId><Amt><InstdAmt Ccy="EUR">1180.00</InstdAmt></Amt><CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt><Cdtr><Nm>Muller Sohne GmbH</Nm></Cdtr><CdtrAcct><Id><IBAN>DE89370400440532013000</IBAN></Id></CdtrAcct><RmtInf><Ustrd>Invoice 1001</Ustrd></RmtInf></CdtTrfTxInf><CdtTrfTxInf><PmtId><EndToEndId>INV-1002</EndToEndId></PmtId><Amt><InstdAmt Ccy="EUR">50.50</InstdAmt></Amt><CdtrAgt><FinInstnId><Othr><Id>NOTPROVIDED</Id></Othr></FinInstnId></CdtrAgt><Cdtr><Nm>Bakker</Nm></Cdtr><CdtrAcct><Id><IBAN>NL02ABNA0123456789</IBAN></Id></CdtrAcct></CdtTrfTxInf></PmtInf></CstmrCdtTrfInitn></Document>
`;

describe("SEPA credit transfer export", () => {
  it(`writes a ${SPEC_PINS.pain001v09} file that matches the golden`, () => {
    expect(sepaCreditTransferXml(FILE)).toBe(GOLDEN);
  });

  it("is well formed with the structure the schema requires", () => {
    const parser = new XMLParser({
      ignoreAttributes: false,
      parseTagValue: false,
    });

    const document = parser.parse(sepaCreditTransferXml(FILE)).Document;
    const header = document.CstmrCdtTrfInitn.GrpHdr;
    const payment = document.CstmrCdtTrfInitn.PmtInf;

    expect(document["@_xmlns"]).toBe(
      `urn:iso:std:iso:20022:tech:xsd:${SPEC_PINS.pain001v09}`,
    );
    expect(Object.keys(header)).toEqual([
      "MsgId",
      "CreDtTm",
      "NbOfTxs",
      "CtrlSum",
      "InitgPty",
    ]);
    expect(header.NbOfTxs).toBe(String(payment.CdtTrfTxInf.length));
    expect(payment.PmtMtd).toBe("TRF");
    expect(payment.ReqdExctnDt.Dt).toMatch(/^\d{4}-\d{2}-\d{2}$/);

    const sum = payment.CdtTrfTxInf.reduce(
      (total: number, each: { Amt: { InstdAmt: { "#text": string } } }) =>
        total + Number(each.Amt.InstdAmt["#text"]),
      0,
    );

    expect(sum.toFixed(2)).toBe(header.CtrlSum);
    expect(payment.CtrlSum).toBe(header.CtrlSum);

    for (const each of payment.CdtTrfTxInf) {
      expect(each.PmtId.EndToEndId.length).toBeLessThanOrEqual(35);
      expect(each.CdtrAcct.Id.IBAN).toMatch(/^[A-Z]{2}\d{2}[A-Z0-9]+$/);
      expect(each.Amt.InstdAmt["@_Ccy"]).toBe("EUR");
    }
  });

  it.each([
    ["an empty file", { transfers: [] }, /at least one transfer/],
    [
      "a currency other than EUR",
      {
        transfers: [
          {
            endToEndId: "A",
            amount: money(100n, "USD"),
            creditorName: "A",
            creditorIban: "NL02ABNA0123456789",
          },
        ],
      },
      /in EUR/,
    ],
    [
      "a repeated end to end id",
      { transfers: [FILE.transfers[0]!, FILE.transfers[0]!] },
      /repeats/,
    ],
    [
      "a debtor name without SEPA characters",
      { debtorName: "€€" },
      /SEPA character/,
    ],
    ["a bad debtor BIC", { debtorBic: "123" }, /not a BIC/],
    [
      "an end to end id with a space",
      { transfers: [{ ...FILE.transfers[0]!, endToEndId: "A B" }] },
      /without spaces/,
    ],
    [
      "a transfer of zero",
      { transfers: [{ ...FILE.transfers[0]!, amount: money(0n, "EUR") }] },
      /more than zero/,
    ],
    ["a bad debtor IBAN", { debtorIban: "NL00" }, /not an IBAN/],
    ["a bad execution date", { executionOn: "02-11-2026" }, /YYYY-MM-DD/],
  ])("refuses %s", (_name, change, message) => {
    expect(() => sepaCreditTransferXml({ ...FILE, ...change })).toThrow(
      message,
    );
  });
});
