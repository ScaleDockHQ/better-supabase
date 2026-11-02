import type { Invoice } from "../../blocks/invoices/invoices.ts";
import type {
  EInvoiceChannel,
  EInvoiceContext,
  EInvoiceDocument,
} from "../../e-invoicing/channel.ts";
import type { EInvoiceEndpoint } from "../../e-invoicing/party.ts";
import type { ConformanceReport } from "../conformance.ts";

import { conform, expect } from "../conformance.ts";

export interface TestEInvoiceChannelOptions {
  readonly organizationId: string;
  /** A document the channel accepts, such as the output of `peppolBis3Format`. */
  readonly document: EInvoiceDocument;
  /** The invoice behind the document. */
  readonly invoice: Invoice;
  /** A participant the channel can deliver to. */
  readonly recipient: EInvoiceEndpoint;
  /** For a channel with `lookup`: a participant that is not on the network. */
  readonly unknownRecipient?: EInvoiceEndpoint;
}

const states: ReadonlySet<string> = new Set([
  "pending",
  "delivered",
  "rejected",
]);

/**
 * Runs the `EInvoiceChannel` contract against `channel`: the API version, a
 * send that returns a message id, and, for each optional method it has, a
 * participant lookup, a delivery status and a receive that returns readable
 * documents. Run it against an access point's test environment: it sends one
 * document.
 */
export function testEInvoiceChannel(
  channel: EInvoiceChannel,
  options: TestEInvoiceChannelOptions,
): Promise<ConformanceReport> {
  const context: EInvoiceContext = { organizationId: options.organizationId };
  let messageId: string | undefined;

  const sent = async (): Promise<string> => {
    messageId ??= (
      await channel.send(options.document, {
        ...context,
        recipient: options.recipient,
        invoice: options.invoice,
      })
    ).messageId;

    return messageId;
  };

  return conform(`EInvoiceChannel "${channel.key}"`, [
    [
      "has apiVersion 1 and a key",
      () => {
        const version: unknown = channel.apiVersion;
        expect(version === 1, `apiVersion is ${String(version)}`);
        expect(channel.key.length > 0, "key is empty");
      },
    ],
    [
      "sends a document and returns a message id",
      async () => {
        const id = await sent();
        expect(id.length > 0, "messageId is empty");
      },
    ],
    [
      "finds a participant on the network, and not an unknown one",
      async () => {
        if (channel.lookup === undefined) {
          return;
        }

        const found = await channel.lookup(options.recipient, context);
        expect(found, "lookup did not find the recipient");

        if (options.unknownRecipient !== undefined) {
          const missing = await channel.lookup(
            options.unknownRecipient,
            context,
          );

          expect(!missing, "lookup found the unknown participant");
        }
      },
    ],
    [
      "reports a state for a sent message, with a reason when rejected",
      async () => {
        if (channel.status === undefined) {
          return;
        }

        const status = await channel.status(await sent(), context);

        expect(states.has(status.state), "status.state is not a known state");
        expect(
          status.state !== "rejected" ||
            (status.reason !== undefined && status.reason.length > 0),
          "a rejected status has no reason",
        );
      },
    ],
    [
      "receives documents that carry a message id and XML",
      async () => {
        if (channel.receive === undefined) {
          return;
        }

        for (const item of await channel.receive(context)) {
          expect(item.messageId.length > 0, "a received document has no id");
          expect(item.xml.length > 0, `${item.messageId} has no XML`);
        }
      },
    ],
  ]);
}
