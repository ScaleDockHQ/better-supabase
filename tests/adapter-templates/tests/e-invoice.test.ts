import "temporal-polyfill/global";
import type { Invoice } from "better-supabase/blocks/invoices";

import { testEInvoiceChannel } from "better-supabase/testing";
import { describe, expect, it } from "vitest";

import {
  createEInvoiceChannel,
  exampleEInvoiceFormat,
} from "../src/e-invoice.ts";
import { fakeFetch, OPTIONS } from "./fake-fetch.ts";

// SAFETY: the format reads only these fields; a full invoice needs the lines and totals it ignores.
const issued = {
  id: "i1",
  kind: "invoice",
  identifier: "INV-2026-0042",
  issuedOn: Temporal.PlainDate.from("2026-10-30"),
  currency: "EUR",
} as unknown as Invoice;

// SAFETY: the format reads only these fields, as for `issued`.
const credit = {
  id: "i3",
  kind: "credit_note",
  identifier: "CN-2026-0007",
  issuedOn: Temporal.PlainDate.from("2026-10-31"),
  currency: "EUR",
} as unknown as Invoice;

// SAFETY: a draft has no identifier or issue date, the only fields the format checks.
const draft = { id: "i2", currency: "EUR" } as unknown as Invoice;

const context = { organizationId: "org-1" };
const recipient = { scheme: "0106", id: "12345678" };

describe("e-invoice format", () => {
  it("renders an issued invoice with its number", async () => {
    const document = await exampleEInvoiceFormat.render(issued, context);

    expect(exampleEInvoiceFormat.apiVersion).toBe(1);
    expect(document.type).toBe("Invoice");
    expect(document.id).toBe("INV-2026-0042");
    expect(document.xml).toContain("<ID>INV-2026-0042</ID>");
  });

  it("renders a credit note as a CreditNote document", async () => {
    const document = await exampleEInvoiceFormat.render(credit, context);

    expect(document.type).toBe("CreditNote");
    expect(document.xml).toMatch(/^<CreditNote>/);
  });

  it("throws for a draft", () => {
    expect(() => exampleEInvoiceFormat.render(draft, context)).toThrow(
      /issued/,
    );
  });
});

describe("e-invoice channel", () => {
  it("passes the EInvoiceChannel conformance block", async () => {
    const channel = createEInvoiceChannel({
      ...OPTIONS,
      fetch: fakeFetch((call) => ({
        json:
          call.method === "POST"
            ? { id: "msg-1" }
            : { state: "rejected", reason: "unknown receiver" },
      })).fetch,
    });

    await expect(
      testEInvoiceChannel(channel, {
        organizationId: context.organizationId,
        document: await exampleEInvoiceFormat.render(issued, context),
        invoice: issued,
        recipient,
      }),
    ).resolves.toBeDefined();
  });

  it("sends to the recipient with an idempotency key and answers the message id", async () => {
    const { fetch, calls } = fakeFetch(() => ({ json: { id: "msg-1" } }));
    const channel = createEInvoiceChannel({ ...OPTIONS, fetch });
    const document = await exampleEInvoiceFormat.render(issued, context);

    expect(channel.apiVersion).toBe(1);
    await expect(
      channel.send(document, { ...context, recipient, invoice: issued }),
    ).resolves.toEqual({ messageId: "msg-1" });
    expect(calls[0]?.headers.get("idempotency-key")).toBe("i1");
    expect(calls[0]?.body).toMatchObject({ recipient });
  });

  it("reads the delivery status, with a reason when rejected", async () => {
    const channel = createEInvoiceChannel({
      ...OPTIONS,
      fetch: fakeFetch(() => ({
        json: { state: "rejected", reason: "unknown receiver" },
      })).fetch,
    });

    await expect(channel.status?.("msg-1", context)).resolves.toEqual({
      state: "rejected",
      reason: "unknown receiver",
    });
  });

  it("rejects an unknown state", async () => {
    const channel = createEInvoiceChannel({
      ...OPTIONS,
      fetch: fakeFetch(() => ({ json: { state: "lost" } })).fetch,
    });

    await expect(channel.status?.("msg-1", context)).rejects.toThrow(
      /unknown state/,
    );
  });

  it("rejects when the access point fails", async () => {
    const channel = createEInvoiceChannel({
      ...OPTIONS,
      fetch: fakeFetch(() => ({ status: 500 })).fetch,
    });

    const document = await exampleEInvoiceFormat.render(issued, context);

    await expect(
      channel.send(document, { ...context, recipient, invoice: issued }),
    ).rejects.toThrow(/HTTP 500/);
  });
});
