import { describe, expect, it } from "vitest";

import type {
  EInvoiceChannel,
  EInvoiceFormat,
  Invoice,
} from "../../../src/blocks/invoices/index.ts";

import {
  eInvoiceChannelOf,
  eInvoiceFormatOf,
  sendEInvoice,
} from "../../../src/blocks/invoices/index.ts";

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
    });

    expect(sent).toEqual(["INV-1.xml"]);
    expect(result.ok && result.data).toMatchObject({
      invoiceId: "i1",
      format: "ubl-reference",
      channel: "memory",
      externalRef: "ref-1",
    });
  });

  it.each(["draft", "void"])("refuses a %s invoice", async (status) => {
    const { channel, sent } = memoryChannel();

    const result = await sendEInvoice({
      invoice: invoice(status),
      format: ubl,
      channel,
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
