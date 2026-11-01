import { describe, expect, it } from "vitest";

import type { EInvoiceChannel } from "../../../src/e-invoicing/index.ts";

import { createInvoices } from "../../../src/blocks/invoices/index.ts";
import {
  eInvoiceChannelOf,
  eInvoiceFormatOf,
  peppolBis3Format,
} from "../../../src/e-invoicing/index.ts";

type Row = Record<string, unknown>;

const delivery = (over: Row = {}): Row => ({
  id: "d1",
  organizationId: "o",
  invoiceId: "i1",
  direction: "outbound",
  format: "peppol-bis-3",
  channel: "memory",
  messageId: "m-1",
  state: "pending",
  ...over,
});

function transport(results: Record<string, (args: Row) => unknown>) {
  const calls: [string, Row][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Row) {
      calls.push([fn, args]);
      const result = results[fn];

      return result
        ? Promise.resolve(result(args))
        : Promise.reject(new Error(`unexpected ${fn}`));
    },
  };
}

const format = {
  apiVersion: 1 as const,
  key: "fake",
  render: (
    invoice: { identifier?: string },
    context: { endpoints?: unknown },
  ) => ({
    type: "Invoice" as const,
    id: invoice.identifier ?? "",
    xml: `<Invoice>${JSON.stringify(context.endpoints)}</Invoice>`,
  }),
};

function memoryChannel(extra: Partial<EInvoiceChannel> = {}) {
  const sent: string[] = [];

  const channel: EInvoiceChannel = {
    apiVersion: 1,
    key: "memory",
    send(document, context) {
      sent.push(`${document.id}->${context.recipient.id}`);

      return Promise.resolve({ messageId: `m-${sent.length}` });
    },
    ...extra,
  };

  return { channel, sent };
}

// SAFETY: the methods read only these fields.
const invoice = (status: string) =>
  ({ id: "i1", organizationId: "o", identifier: "INV-1", status }) as never;

const buyer = { scheme: "0106", id: "12345678" };

function client(over: Record<string, (args: Row) => unknown> = {}) {
  const t = transport({
    invoice_e_endpoints: () => ({ seller: { scheme: "0106", id: "1" }, buyer }),
    list_e_invoice_deliveries: () => null,
    record_e_invoice_delivery: () => ({ created: true, delivery: delivery() }),
    ...over,
  });

  return { t, invoices: createInvoices({ transport: t }) };
}

describe("sendEInvoice", () => {
  it("renders with the stored endpoints, sends and logs the delivery", async () => {
    const { t, invoices } = client();
    const { channel, sent } = memoryChannel();

    const result = await invoices.sendEInvoice(invoice("issued"), {
      format,
      channel,
    });

    expect(sent).toEqual(["INV-1->12345678"]);
    expect(result.ok && result.data.delivery.state).toBe("pending");
    expect(result.ok && result.data.document.xml).toContain("12345678");

    const logged = t.calls.find(([fn]) => fn === "record_e_invoice_delivery");

    expect(logged?.[1]).toMatchObject({
      tenant: "o",
      direction: "outbound",
      channel: "memory",
      message_id: "m-1",
      invoice: "i1",
    });
    expect(logged?.[1]["document_hash"]).toMatch(/^[0-9a-f]{64}$/);
  });

  it.each(["draft", "void"])("refuses a %s invoice", async (status) => {
    const { invoices } = client();
    const { channel, sent } = memoryChannel();

    const result = await invoices.sendEInvoice(invoice(status), {
      format,
      channel,
    });

    expect(result.ok ? undefined : result.error.hint).toBe(
      "EINVOICE_NOT_ISSUED",
    );
    expect(sent).toHaveLength(0);
  });

  it("needs a participant id on the buyer", async () => {
    const { invoices } = client({ invoice_e_endpoints: () => ({}) });
    const { channel } = memoryChannel();

    const result = await invoices.sendEInvoice(invoice("issued"), {
      format,
      channel,
    });

    expect(result.ok ? undefined : result.error.hint).toBe(
      "EINVOICE_NO_RECIPIENT",
    );
  });

  it("refuses an unreachable buyer", async () => {
    const { invoices } = client();

    const { channel, sent } = memoryChannel({
      lookup: () => Promise.resolve(false),
    });

    const result = await invoices.sendEInvoice(invoice("issued"), {
      format,
      channel,
    });

    expect(result.ok ? undefined : result.error.hint).toBe(
      "EINVOICE_RECIPIENT_UNREACHABLE",
    );
    expect(sent).toHaveLength(0);
  });

  it("refuses a second send unless resend is set", async () => {
    const { invoices } = client({
      list_e_invoice_deliveries: () => [delivery({ state: "delivered" })],
    });

    const { channel, sent } = memoryChannel();

    const first = await invoices.sendEInvoice(invoice("issued"), {
      format,
      channel,
    });

    expect(first.ok ? undefined : first.error.hint).toBe(
      "EINVOICE_ALREADY_SENT",
    );

    const again = await invoices.sendEInvoice(invoice("issued"), {
      format,
      channel,
      resend: true,
    });

    expect(again.ok).toBe(true);
    expect(sent).toHaveLength(1);
  });

  it("returns a failing channel as an error result", async () => {
    const { invoices } = client();

    const result = await invoices.sendEInvoice(invoice("issued"), {
      format,
      channel: {
        apiVersion: 1,
        key: "down",
        send: () => Promise.reject(new Error("access point down")),
      },
    });

    expect(result.ok).toBe(false);
  });

  it("names the message id when logging fails after the send", async () => {
    const { invoices } = client({
      record_e_invoice_delivery: () => Promise.reject(new Error("db down")),
    });
    const { channel, sent } = memoryChannel();

    const result = await invoices.sendEInvoice(invoice("issued"), {
      format,
      channel,
    });

    expect(sent).toHaveLength(1);
    expect(result.ok ? undefined : result.error.message).toContain("m-1");
  });

  it("records a delivery the channel already accepted", async () => {
    const { t, invoices } = client();

    const result = await invoices.recordEInvoiceDelivery(invoice("issued"), {
      channel: "memory",
      format: "peppol-bis-3",
      messageId: "m-1",
    });

    expect(result.ok && result.data.messageId).toBe("m-1");
    expect(t.calls.at(-1)).toEqual([
      "record_e_invoice_delivery",
      {
        tenant: "o",
        direction: "outbound",
        channel: "memory",
        message_id: "m-1",
        format: "peppol-bis-3",
        invoice: "i1",
      },
    ]);
  });

  it("rejects another apiVersion", () => {
    expect(() =>
      // SAFETY: simulates a format built for a newer API.
      eInvoiceFormatOf({ ...format, apiVersion: 2 } as never),
    ).toThrow(TypeError);
    expect(() =>
      // SAFETY: simulates a channel built for a newer API.
      eInvoiceChannelOf({ ...memoryChannel().channel, apiVersion: 2 } as never),
    ).toThrow(TypeError);
  });
});

describe("syncEInvoices", () => {
  it("moves pending deliveries to the state the channel reports", async () => {
    const { t, invoices } = client({
      list_e_invoice_deliveries: () => [
        delivery({ id: "d1", messageId: "m-1" }),
        delivery({ id: "d2", messageId: "m-2" }),
        delivery({ id: "d3", messageId: "m-3", channel: "other" }),
      ],
      set_e_invoice_delivery_state: (args) =>
        delivery({ id: args["delivery"], state: args["state"] }),
    });

    const { channel } = memoryChannel({
      status: (id) =>
        Promise.resolve(
          id === "m-1"
            ? { state: "delivered" }
            : { state: "rejected", reason: "unknown receiver" },
        ),
    });

    const result = await invoices.syncEInvoices("o", { channel });

    expect(result.ok && result.data).toEqual({
      checked: 2,
      delivered: 1,
      rejected: 1,
    });
    expect(
      t.calls.filter(([fn]) => fn === "set_e_invoice_delivery_state"),
    ).toHaveLength(2);
  });

  it("refuses a channel that can't report status", async () => {
    const { invoices } = client();
    const { channel } = memoryChannel();

    const result = await invoices.syncEInvoices("o", { channel });

    expect(result.ok ? undefined : result.error.hint).toBe(
      "EINVOICE_CHANNEL_UNSUPPORTED",
    );
  });
});

describe("receiveEInvoices", () => {
  it("logs unreadable documents as unmatched", async () => {
    const { t, invoices } = client({
      record_e_invoice_delivery: () => ({
        created: true,
        delivery: delivery({ direction: "inbound", state: "unmatched" }),
      }),
      set_e_invoice_delivery_state: (args) =>
        delivery({ direction: "inbound", state: args["state"] }),
    });

    const { channel } = memoryChannel({
      receive: () =>
        Promise.resolve([
          { type: "Invoice", id: "X", xml: "<nope/>", messageId: "in-1" },
        ]),
    });

    const result = await invoices.receiveEInvoices("o", { channel });

    expect(result.ok && result.data.unmatched).toHaveLength(1);
    expect(result.ok && result.data.created).toHaveLength(0);
    expect(
      t.calls.find(([fn]) => fn === "set_e_invoice_delivery_state")?.[1],
    ).toMatchObject({ state: "unmatched" });
  });

  it("skips documents already in the log", async () => {
    const { invoices } = client({
      record_e_invoice_delivery: () => ({
        created: false,
        delivery: delivery({ direction: "inbound", state: "received" }),
      }),
    });

    const { channel } = memoryChannel({
      receive: () =>
        Promise.resolve([
          { type: "Invoice", id: "X", xml: "<nope/>", messageId: "in-1" },
        ]),
    });

    const result = await invoices.receiveEInvoices("o", { channel });

    expect(result.ok && result.data.skipped).toBe(1);
  });
});

describe("endpoints", () => {
  it("sets and clears a participant id", async () => {
    const { t, invoices } = client({
      set_invoice_e_endpoint: (args) =>
        args["scheme"] === null
          ? null
          : { scheme: args["scheme"], id: args["endpoint_id"] },
    });

    const set = await invoices.setEInvoiceEndpoint("o", "company", "c1", buyer);

    const cleared = await invoices.setEInvoiceEndpoint(
      "o",
      "company",
      "c1",
      null,
    );

    expect(set.ok && set.data).toEqual(buyer);
    expect(cleared.ok && cleared.data).toBeNull();
    expect(t.calls[0]?.[1]).toMatchObject({
      party_kind: "company",
      scheme: "0106",
    });
  });

  it("peppolBis3Format hands the stored endpoints to parties", async () => {
    let seen: unknown;

    const bis = peppolBis3Format({
      parties: (_invoice, context) => {
        seen = context.endpoints;
        throw new Error("stop");
      },
    });

    await expect(
      Promise.resolve().then(() =>
        bis.render(invoice("issued"), {
          organizationId: "o",
          endpoints: { buyer },
        }),
      ),
    ).rejects.toThrow("stop");
    expect(seen).toEqual({ buyer });
  });
});
