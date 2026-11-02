import { describe, expect, it } from "vitest";

import { parseMt940 } from "../../../src/blocks/banking/mt940.ts";

const wrap = (...fields: string[]): string =>
  [
    ":20:REF",
    ":25:NL91ABNA0417164300EUR",
    ":60F:C261001EUR10,",
    ...fields,
    ":62F:C261002EUR20,",
  ].join("\n");

const only = (...fields: string[]) => {
  const [statement] = parseMt940(wrap(...fields));

  if (!statement) {
    throw new Error("no statement parsed");
  }

  return statement;
};

describe("parseMt940 edge cases", () => {
  it("dates two-digit years and separate entry dates", () => {
    const statement = only(":61:9910150917DR12,5NTRFNONREF//BANK-1");

    expect(statement.transactions[0]).toMatchObject({
      valueOn: "1999-10-15",
      bookedOn: "1999-09-17",
      externalId: "BANK-1",
    });
    expect(statement.transactions[0]?.amount.amount).toBe(-1250n);
  });

  it("treats reversed debits as credits and skips NONREF ids", () => {
    const [transaction] = only(":61:261001RD5,NTRFNONREF//NONREF").transactions;

    expect(transaction?.amount.amount).toBe(500n);
    expect(transaction?.externalId).toBeUndefined();
  });

  it("falls back to the customer reference when the bank has none", () => {
    expect(only(":61:261001C5,NTRFCUST-1").transactions[0]?.externalId).toBe(
      "CUST-1",
    );
  });

  it("reads SEPA fields with the counterparty block and plain remittance", () => {
    const [transaction] = only(
      ":61:261001C5,NTRF1//B",
      ":86:/EREF/NOTPROVIDED/CNTP/NL02RABO0123456789/RABONL2U/Acme/REMI/USTD//Thanks/",
    ).transactions;

    expect(transaction).toMatchObject({
      counterpartyIban: "NL02RABO0123456789",
      counterpartyName: "Acme",
      remittance: "Thanks",
    });
    expect(transaction?.endToEndId).toBeUndefined();
  });

  it("ignores an invalid IBAN and an empty :86:", () => {
    const [bad, empty] = only(
      ":61:261001C5,NTRF1//B",
      ":86:/IBAN/nope/NAME/ Padded /REMI/hello",
      ":61:261001C5,NTRF1//C",
      ":86:",
    ).transactions;

    expect(bad).toMatchObject({
      counterpartyName: "Padded",
      remittance: "hello",
    });
    expect(bad?.counterpartyIban).toBeUndefined();
    expect(empty?.counterpartyName).toBeUndefined();
    expect(empty?.remittance).toBeUndefined();
  });

  it("reads German subfields without a bank-supplied name or IBAN", () => {
    const [transaction] = only(
      ":61:261001C5,NTRF1//B",
      ":86:166?00BUCHUNG?20EREF+NOTPROVIDED SVWZ+Miete?21Oktober?31bad?32Muster?33 GmbH",
    ).transactions;

    expect(transaction).toMatchObject({
      counterpartyName: "Muster GmbH",
      remittance: "MieteOktober",
    });
    expect(transaction?.counterpartyIban).toBeUndefined();
    expect(transaction?.endToEndId).toBeUndefined();

    const [plain] = only(
      ":61:261001C5,NTRF1//B",
      ":86:166?20no keys here",
    ).transactions;

    expect(plain?.remittance).toBe("no keys here");
    expect(plain?.counterpartyName).toBeUndefined();
  });

  it("keeps free text from :86: as the remittance", () => {
    expect(
      only(":61:261001C5,NTRF1//B", ":86:line one\nline two").transactions[0]
        ?.remittance,
    ).toBe("line one line two");
  });

  it("uses the account identification when the account is no IBAN", () => {
    const [statement] = parseMt940(":20:A\n:25:ACCOUNT 7\n:60F:C261001EUR1,\n");

    expect(statement?.account).toEqual({
      identification: "ACCOUNT 7",
      currency: "EUR",
    });
    expect(statement?.closingBalance).toBeUndefined();
    expect(statement?.untilOn).toBeUndefined();
    expect(statement?.reference).toBe("A");
  });

  it("reads a closing balance without an opening one and the sequence number", () => {
    const [statement] = parseMt940(":20:A\n:28C:7/1\n:62M:D261003USD2,5\n");

    expect(statement).toMatchObject({
      reference: "A/7/1",
      untilOn: "2026-10-03",
      account: { identification: "", currency: "USD" },
    });
    expect(statement?.fromOn).toBeUndefined();
    expect(statement?.closingBalance?.amount).toBe(-250n);
  });

  it("strips SWIFT block headers and ends on the block trailer", () => {
    const statements = parseMt940(
      `{1:F01BANKNL2AXXXX0000000000}{4:\n${wrap(":61:261001C5,NTRF1//B")}\n-}`,
    );

    expect(statements).toHaveLength(1);
    expect(statements[0]?.transactions).toHaveLength(1);
  });
});
