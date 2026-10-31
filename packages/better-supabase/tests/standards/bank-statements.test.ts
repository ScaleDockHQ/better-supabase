import { describe, expect, it } from "vitest";

import { parseCamt053 } from "../../src/blocks/banking/camt053.ts";
import { parseMt940 } from "../../src/blocks/banking/mt940.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const camt = (
  version: string,
): string => `<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:${version}">
  <BkToCstmrStmt>
    <GrpHdr><MsgId>M</MsgId><CreDtTm>2026-10-02T06:00:00</CreDtTm></GrpHdr>
    <Stmt>
      <Id>S-1</Id>
      <Acct><Id><IBAN>NL91ABNA0417164300</IBAN></Id><Ccy>EUR</Ccy></Acct>
      <Bal><Tp><CdOrPrtry><Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">10.00</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2026-10-01</Dt></Dt></Bal>
      <Bal><Tp><CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy="EUR">12.50</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2026-10-01</Dt></Dt></Bal>
      <Ntry>
        <Amt Ccy="EUR">2.50</Amt><CdtDbtInd>CRDT</CdtDbtInd>
        <Sts>${version.endsWith("08") ? "<Cd>BOOK</Cd>" : "BOOK"}</Sts>
        <BookgDt><Dt>2026-10-01</Dt></BookgDt>
        <AcctSvcrRef>B-1</AcctSvcrRef>
      </Ntry>
    </Stmt>
  </BkToCstmrStmt>
</Document>`;

describe("camt.053 bank-to-customer statements", () => {
  it.each([SPEC_PINS.camt053v02, SPEC_PINS.camt053v08])(
    "reads the pinned %s schema",
    async (version) => {
      const [statement] = await parseCamt053(camt(version));

      expect(statement?.format).toBe("camt053");
      expect(statement?.transactions).toHaveLength(1);
      expect(statement?.closingBalance?.amount).toBe(1250n);
    },
  );
});

describe("MT940 customer statements", () => {
  it(`reads the ${SPEC_PINS.mt940} field layout`, () => {
    const [statement] = parseMt940(
      [
        ":20:STMT1",
        ":25:NL91ABNA0417164300EUR",
        ":28C:1/1",
        ":60F:C261001EUR10,00",
        ":61:2610011001C2,50NTRFNONREF//B-1",
        ":86:/NAME/Acme/REMI/USTD//Invoice 42",
        ":62F:C261001EUR12,50",
        "-",
      ].join("\r\n"),
    );

    expect(statement?.format).toBe("mt940");
    expect(statement?.transactions[0]?.externalId).toBe("B-1");
    expect(statement?.closingBalance?.amount).toBe(1250n);
  });
});
