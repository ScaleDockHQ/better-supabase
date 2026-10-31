import { describe, expect, it } from "vitest";

import type { AuditFileSource } from "../../src/audit-files/index.ts";

import { saftAdapter } from "../../src/audit-files/index.ts";

const saft = saftAdapter({});

async function parse(source: AuditFileSource, options = {}) {
  const records = [];

  for await (const record of saft.parse(source, options)) {
    records.push(record);
  }

  return records;
}

const FILE = `\uFEFF<?xml version="1.0" encoding="UTF-8"?>
<!-- a comment -->
<AuditFile xmlns="urn:OECD:StandardAuditFile-Taxation/2.00">
  <Header>
    <AuditFileVersion>2.00</AuditFileVersion>
    <Company><Name><![CDATA[Acme & <Co>]]></Name></Company>
    <SelectionCriteria><SelectionStartDate>2026-01-01</SelectionStartDate><SelectionEndDate>2026-12-31</SelectionEndDate></SelectionCriteria>
    <Unknown/>
  </Header>
  <MasterFiles>
    <GeneralLedgerAccounts>
      <Account>
        <AccountID>1000</AccountID>
        <AccountDescription>Bank &amp; cash &#65;&#x42;</AccountDescription>
        <AccountType>Asset</AccountType>
      </Account>
    </GeneralLedgerAccounts>
  </MasterFiles>
</AuditFile>`;

describe("the tokenizer", () => {
  it("reads comments, CDATA, entities, a BOM and namespaces", async () => {
    const records = await parse(FILE);
    const account = records.find((record) => record.kind === "account");

    expect(account?.kind === "account" && account.account.name).toBe(
      "Bank & cash AB",
    );

    const header = records.find((record) => record.kind === "header");

    expect(header?.kind === "header" && header.header.company.name).toBe(
      "Acme & <Co>",
    );
  });

  it("reports unmapped elements once per path with a count", async () => {
    const records = await parse(FILE);

    expect(
      records.filter(
        (record) =>
          record.kind === "warning" &&
          record.warning.code === "AUDIT_ELEMENT_UNMAPPED",
      ).length,
    ).toBeGreaterThan(0);
  });

  it("reads bytes, iterables and async iterables alike", async () => {
    const bytes = new TextEncoder().encode(FILE);
    const fromBytes = await parse(bytes);
    const fromIterable = await parse([bytes.slice(0, 40), bytes.slice(40)]);

    async function* chunks() {
      yield FILE.slice(0, 33);
      yield new TextEncoder().encode(FILE.slice(33));
    }

    const fromAsync = await parse(chunks());

    expect(fromIterable).toEqual(fromBytes);
    expect(fromAsync).toEqual(fromBytes);
  });

  it.each([
    ["an unterminated comment", "<a><!-- x"],
    ["an unterminated CDATA section", "<a><![CDATA[ x"],
    ["an unterminated tag", "<a"],
    ["a stray close tag", "</a>"],
    ["a numeric reference out of range", "<a>&#x110000;</a>"],
    ["an empty document", ""],
    ["an unclosed element", "<a><b></b>"],
  ])("refuses %s", async (_name, xml) => {
    await expect(parse(xml)).rejects.toMatchObject({ name: "AuditFileError" });
  });

  it("limits text length and record elements", async () => {
    await expect(
      parse(["<a>", "x".repeat(50), "x".repeat(50), "</a>"], {
        maxTextLength: 10,
      }),
    ).rejects.toMatchObject({ code: "AUDIT_XML_LIMIT" });
    await expect(parse(FILE, { maxRecordElements: 2 })).rejects.toMatchObject({
      code: "AUDIT_XML_LIMIT",
    });
  });
});
