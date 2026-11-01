import { describe, expect, it } from "vitest";

import type {
  EInvoiceChannel,
  EInvoiceFormat,
  Invoice,
  InvoiceDelivery,
  InvoiceDeliveryInput,
  InvoiceEInvoices,
} from "../../../src/blocks/invoices/index.ts";
import type { BlockCall } from "../../../src/blocks/shared.ts";

import { invoiceEInvoices } from "../../../src/blocks/invoices/e-invoice.ts";
import {
  eInvoiceChannelOf,
  eInvoiceFormatOf,
  sendEInvoice,
} from "../../../src/blocks/invoices/index.ts";
import { AsyncResult, err, ok } from "../../../src/core/result.ts";

/** A reference format that renders a minimal UBL-like document. */
const ubl: EInvoiceFormat = {
  apiVersion: 1,
  key: "ubl-reference",
  render: (invoice) => ({
    body: `<Invoice><ID>${invoice.identifier}</ID></Invoice>`,
    filename: `${invoice.identifier}.xml`,
    contentType: "application/xml",
  }),
};

function memoryChannel() {
  const sent: string[] = [];

  const channel: EInvoiceChannel = {
    apiVersion: 1,
    key: "memory",
    send(document) {
      sent.push(document.filename);

      return Promise.resolve({ externalRef: `ref-${sent.length}` });
    },
  };

  return { channel, sent };
}

function memoryInvoices() {
  const kept: { invoiceId: string; input: InvoiceDeliveryInput }[] = [];

  const invoices: Pick<InvoiceEInvoices, "recordEInvoice"> = {
    recordEInvoice: (invoiceId, input) => {
      kept.push({ invoiceId, input });

      return AsyncResult.from(() =>
        Promise.resolve(
          ok({
            id: `d${kept.length}`,
            invoiceId,
            ...input,
            sentAt: Temporal.Now.instant(),
          }),
        ),
      );
    },
  };

  return { invoices, kept };
}

// SAFETY: the sender reads only these fields.
const invoice = (status: string) =>
  ({
    id: "i1",
    organizationId: "o",
    identifier: "INV-1",
    status,
  }) as unknown as Invoice;

describe("sendEInvoice", () => {
  it("renders and sends an issued invoice", async () => {
    const { channel, sent } = memoryChannel();

    const result = await sendEInvoice({
      invoice: invoice("sent"),
      format: ubl,
      channel,
      invoices: memoryInvoices().invoices,
    });

    expect(sent).toEqual(["INV-1.xml"]);
    expect(result.ok && result.data).toMatchObject({
      invoiceId: "i1",
      format: "ubl-reference",
      channel: "memory",
      externalRef: "ref-1",
    });
  });

  it("keeps the channel's externalRef through recordEInvoice", async () => {
    const { channel } = memoryChannel();
    const { invoices, kept } = memoryInvoices();

    const result = await sendEInvoice({
      invoice: invoice("sent"),
      format: ubl,
      channel,
      invoices,
    });

    expect(kept).toEqual([
      {
        invoiceId: "i1",
        input: {
          channel: "memory",
          format: "ubl-reference",
          externalRef: "ref-1",
          filename: "INV-1.xml",
        },
      },
    ]);
    expect(result.ok && result.data.deliveryId).toBe("d1");
  });

  it("names the externalRef when keeping it fails", async () => {
    const { channel, sent } = memoryChannel();

    const result = await sendEInvoice({
      invoice: invoice("sent"),
      format: ubl,
      channel,
      invoices: {
        recordEInvoice: () =>
          AsyncResult.from<InvoiceDelivery>(() =>
            Promise.resolve(
              err({ kind: "network", message: "database down", status: 503 }),
            ),
          ),
      },
    });

    expect(sent).toHaveLength(1);
    expect(result.ok ? undefined : result.error.message).toContain("ref-1");
  });

  it.each(["draft", "void"])("refuses a %s invoice", async (status) => {
    const { channel, sent } = memoryChannel();

    const result = await sendEInvoice({
      invoice: invoice(status),
      format: ubl,
      channel,
      invoices: memoryInvoices().invoices,
    });

    expect(result.ok ? undefined : result.error.hint).toBe(
      "EINVOICE_NOT_ISSUED",
    );
    expect(sent).toHaveLength(0);
  });

  it("returns a failing channel as an error result", async () => {
    const result = await sendEInvoice({
      invoice: invoice("sent"),
      format: ubl,
      invoices: memoryInvoices().invoices,
      channel: {
        apiVersion: 1,
        key: "down",
        send: () => Promise.reject(new Error("access point down")),
      },
    });

    expect(result.ok).toBe(false);
  });

  it("passes the abort signal on", async () => {
    let seen: AbortSignal | undefined;
    const controller = new AbortController();

    await sendEInvoice({
      invoice: invoice("sent"),
      format: ubl,
      signal: controller.signal,
      invoices: memoryInvoices().invoices,
      channel: {
        apiVersion: 1,
        key: "spy",
        send(_document, context) {
          seen = context.signal;

          return Promise.resolve({ externalRef: "r" });
        },
      },
    });

    expect(seen).toBe(controller.signal);
  });

  it("rejects another apiVersion", () => {
    expect(() =>
      // SAFETY: simulates a format built for a newer API.
      eInvoiceFormatOf({ ...ubl, apiVersion: 2 } as never),
    ).toThrow(TypeError);
    expect(() =>
      // SAFETY: simulates a channel built for a newer API.
      eInvoiceChannelOf({ ...memoryChannel().channel, apiVersion: 2 } as never),
    ).toThrow(TypeError);
  });
});

describe("invoiceEInvoices", () => {
  const row = {
    id: "d1",
    invoiceId: "i1",
    channel: "peppol",
    format: "ubl",
    externalRef: "ref-1",
    sentAt: "2026-11-01T10:00:00Z",
  };

  function stub() {
    const calls: { fn: string; args: Readonly<Record<string, unknown>> }[] = [];

    const call: BlockCall = (fn, args, then) => {
      calls.push({ fn, args });

      return AsyncResult.from(async () =>
        ok(
          await then(
            fn === "list_invoice_deliveries"
              ? [row, { ...row, id: "d2", filename: "INV-1.xml" }]
              : row,
          ),
        ),
      );
    };

    return { call, calls };
  }

  it("records a delivery and passes a missing filename as null", async () => {
    const { call, calls } = stub();

    const result = await invoiceEInvoices(call).recordEInvoice("i1", {
      channel: "peppol",
      format: "ubl",
      externalRef: "ref-1",
    });

    expect(calls).toEqual([
      {
        fn: "record_invoice_delivery",
        args: {
          invoice: "i1",
          channel: "peppol",
          format: "ubl",
          external_ref: "ref-1",
          filename: null,
        },
      },
    ]);
    expect(result.ok && result.data).toMatchObject({
      id: "d1",
      externalRef: "ref-1",
    });
    expect(result.ok && result.data.filename).toBeUndefined();
  });

  it("passes the filename on", async () => {
    const { call, calls } = stub();

    await invoiceEInvoices(call).recordEInvoice("i1", {
      channel: "peppol",
      format: "ubl",
      externalRef: "ref-1",
      filename: "INV-1.xml",
    });

    expect(calls[0]?.args["filename"]).toBe("INV-1.xml");
  });

  it("lists the deliveries of an invoice", async () => {
    const { call, calls } = stub();

    const result = await invoiceEInvoices(call).eInvoiceDeliveries("i1");

    expect(calls[0]).toEqual({
      fn: "list_invoice_deliveries",
      args: { invoice: "i1" },
    });
    expect(result.ok && result.data.map((d) => d.filename)).toEqual([
      undefined,
      "INV-1.xml",
    ]);
  });
});
