import { describe, expect, it } from "vitest";

import type { EInvoiceChannel } from "../../../src/e-invoicing/index.ts";

import { ConformanceError } from "../../../src/testing/conformance.ts";
import { testEInvoiceChannel } from "../../../src/testing/index.ts";

const recipient = { scheme: "0106", id: "12345678" };
const unknownRecipient = { scheme: "0106", id: "00000000" };

const options = {
  organizationId: "o",
  document: { type: "Invoice" as const, id: "INV-1", xml: "<Invoice/>" },
  // SAFETY: the kit hands the invoice to the channel without reading it.
  invoice: { id: "i1" } as never,
  recipient,
  unknownRecipient,
};

function fullChannel(over: Partial<EInvoiceChannel> = {}): EInvoiceChannel {
  return {
    apiVersion: 1,
    key: "memory",
    send: () => Promise.resolve({ messageId: "m-1" }),
    lookup: (participant) => Promise.resolve(participant.id === recipient.id),
    status: () => Promise.resolve({ state: "delivered" }),
    receive: () =>
      Promise.resolve([
        { type: "Invoice", id: "B-1", xml: "<Invoice/>", messageId: "in-1" },
      ]),
    ...over,
  };
}

async function failures(channel: EInvoiceChannel): Promise<string[]> {
  const error = await testEInvoiceChannel(channel, options).then(
    () => undefined,
    (cause: unknown) => cause,
  );

  expect(error).toBeInstanceOf(ConformanceError);

  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => check.name);
}

describe("testEInvoiceChannel", () => {
  it("passes a channel with every optional method", async () => {
    let sends = 0;

    const report = await testEInvoiceChannel(
      fullChannel({
        send: () => {
          sends += 1;

          return Promise.resolve({ messageId: "m-1" });
        },
      }),
      options,
    );

    expect(report.subject).toBe('EInvoiceChannel "memory"');
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(sends).toBe(1);
  });

  it("passes a send-only channel", async () => {
    const { unknownRecipient: _unknown, ...sendOnly } = options;

    const report = await testEInvoiceChannel(
      {
        apiVersion: 1,
        key: "send-only",
        send: () => Promise.resolve({ messageId: "m-1" }),
      },
      sendOnly,
    );

    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("fails a lookup that finds everyone", async () => {
    expect(
      await failures(fullChannel({ lookup: () => Promise.resolve(true) })),
    ).toEqual(["finds a participant on the network, and not an unknown one"]);
  });

  it("fails a rejected status without a reason and an unknown state", async () => {
    expect(
      await failures(
        fullChannel({ status: () => Promise.resolve({ state: "rejected" }) }),
      ),
    ).toEqual([
      "reports a state for a sent message, with a reason when rejected",
    ]);
    expect(
      await failures(
        // SAFETY: simulates a channel that reports a state outside the union.
        fullChannel({
          status: () => Promise.resolve({ state: "lost" } as never),
        }),
      ),
    ).toEqual([
      "reports a state for a sent message, with a reason when rejected",
    ]);
  });

  it("fails a received document without an id or XML", async () => {
    expect(
      await failures(
        fullChannel({
          receive: () =>
            Promise.resolve([
              { type: "Invoice", id: "B-1", xml: "", messageId: "in-1" },
            ]),
        }),
      ),
    ).toEqual(["receives documents that carry a message id and XML"]);
  });

  it("fails another apiVersion and an empty message id", async () => {
    expect(
      await failures(
        // SAFETY: simulates a channel built for a newer API.
        fullChannel({
          apiVersion: 2 as never,
          send: () => Promise.resolve({ messageId: "" }),
        }),
      ),
    ).toEqual([
      "has apiVersion 1 and a key",
      "sends a document and returns a message id",
    ]);
  });
});
