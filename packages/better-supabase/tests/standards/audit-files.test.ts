import { describe, expect, it } from "vitest";

import {
  SAFT_NAMESPACE,
  XAF_NAMESPACE,
  saftAdapter,
  xafAdapter,
} from "../../src/audit-files/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe(`SAF-T ${SPEC_PINS.saftOecd} and XAF ${SPEC_PINS.xaf}`, () => {
  it("name the pinned releases in their adapters", () => {
    expect(saftAdapter({}).key).toBe(`saft-oecd-${SPEC_PINS.saftOecd}`);
    expect(xafAdapter({}).key).toBe(`xaf-${SPEC_PINS.xaf}`);
    expect(SAFT_NAMESPACE).toBe("urn:OECD:StandardAuditFile-Taxation/2.00");
    expect(XAF_NAMESPACE).toBe("http://www.auditfiles.nl/XAF/3.2");
  });

  it("write the pinned namespace on the root element", () => {
    const books = {
      header: {
        fiscalYear: 2026,
        startDate: "2026-01-01",
        endDate: "2026-12-31",
        currency: "EUR",
        company: { name: "Acme" },
      },
      accounts: [],
      parties: [],
      taxCodes: [],
      journals: [],
      openingBalances: [],
      entries: [],
    };

    expect([...saftAdapter({}).export(books)].join("")).toContain(
      SAFT_NAMESPACE,
    );
    expect([...xafAdapter({}).export(books)].join("")).toContain(XAF_NAMESPACE);
  });
});
