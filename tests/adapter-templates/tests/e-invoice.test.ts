import "temporal-polyfill/global";
import type { Invoice } from "better-supabase/blocks/invoices";

import { describe, expect, it } from "vitest";

import {
  createEInvoiceChannel,
  exampleEInvoiceFormat,
} from "../src/e-invoice.ts";
import { fakeFetch, OPTIONS } from "./fake-fetch.ts";

// SAFETY: the format reads only these fields; a full invoice needs the lines and totals it ignores.
const issued = {
  id: "i1",
  identifier: "INV-2026-0042",
  issuedOn: Temporal.PlainDate.from("2026-10-30"),
  currency: "EUR",
} as unknown as Invoice;

// SAFETY: a draft has no identifier or issue date, the only fields the format checks.
const draft = { id: "i2", currency: "EUR" } as unknown as Invoice;

const context = { organizationId: "org-1" };

describe("e-invoice format", () => {
  it("renders an issued invoice with a file name and a media type", async () => {
    const document = await exampleEInvoiceFormat.render(issued, context);

    expect(exampleEInvoiceFormat.apiVersion).toBe(1);
    expect(document.filename).toBe("INV-2026-0042.xml");
    expect(document.contentType).toBe("application/xml");
    expect(document.body).toContain("<ID>INV-2026-0042</ID>");
  });

  it("throws for a draft", () => {
    expect(() => exampleEInvoiceFormat.render(draft, context)).toThrow(
      /issued/,
    );
  });
});

describe("e-invoice channel", () => {
  it("sends with an idempotency key and answers the network's reference", async () => {
    const { fetch, calls } = fakeFetch(() => ({ json: { id: "ref-1" } }));
    const channel = createEInvoiceChannel({ ...OPTIONS, fetch });
    const document = await exampleEInvoiceFormat.render(issued, context);

    expect(channel.apiVersion).toBe(1);
    await expect(
      channel.send(document, { ...context, invoice: issued }),
    ).resolves.toEqual({ externalRef: "ref-1" });
    expect(calls[0]?.headers.get("idempotency-key")).toBe("i1");
  });

  it("reads the delivery status, with a reason when rejected", async () => {
    const channel = createEInvoiceChannel({
      ...OPTIONS,
      fetch: fakeFetch(() => ({
        json: { state: "rejected", reason: "unknown receiver" },
      })).fetch,
    });

    await expect(channel.status?.("ref-1", context)).resolves.toEqual({
      state: "rejected",
      reason: "unknown receiver",
    });
  });

  it("rejects when the access point fails", async () => {
    const channel = createEInvoiceChannel({
      ...OPTIONS,
      fetch: fakeFetch(() => ({ status: 500 })).fetch,
    });

    const document = await exampleEInvoiceFormat.render(issued, context);

    await expect(
      channel.send(document, { ...context, invoice: issued }),
    ).rejects.toThrow(/HTTP 500/);
  });
});
