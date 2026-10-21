import type {
  DeliveryTransport,
  EmailMessage,
} from "../blocks/notifications/delivery.ts";
import type { ConformanceReport } from "./conformance.ts";

import { mailHeaders } from "../blocks/notifications/delivery.ts";
import { conform, deepFreeze, expect } from "./conformance.ts";

/** What the provider received for one message, as the test's fake reports it. */
export interface ReceivedDelivery {
  readonly idempotencyKey: string;
  readonly headers: Readonly<Record<string, string>>;
}

export interface TestDeliveryTransportOptions {
  /** The sample's recipient. Defaults to `delivered@example.test`. */
  readonly to?: string;
  /**
   * What the provider received, read after the kit sends. When given, the kit
   * checks that the idempotency key and the headers arrived as sent.
   */
  readonly received?: () => Promise<readonly ReceivedDelivery[]>;
}

const KEY = "00000000-0000-4000-8000-00000000d0f0";

/**
 * Runs the `DeliveryTransport` contract against `transport`: API version 1, the
 * `email` channel, a provider name, and one frozen sample message it sends
 * without mutating, with the delivery id as its idempotency key. Throws a
 * `ConformanceError` listing every failed check.
 */
export function testDeliveryTransport(
  transport: DeliveryTransport,
  options: TestDeliveryTransportOptions = {},
): Promise<ConformanceReport> {
  const message: EmailMessage = deepFreeze({
    from: "Conformance <conformance@example.test>",
    to: options.to ?? "delivered@example.test",
    subject: "Conformance check",
    text: "Conformance check",
    category: "notification",
    headers: mailHeaders("notification", {
      url: "https://example.test/unsubscribe",
    }),
  });

  return conform(`DeliveryTransport "${transport.provider}"`, [
    [
      "has apiVersion 1",
      () => {
        const version: unknown = transport.apiVersion;
        expect(version === 1, "apiVersion must be 1");
      },
    ],
    [
      "sends on the email channel",
      () => {
        const channel: unknown = transport.channel;
        expect(
          channel === "email",
          `channel must be "email", got ${String(channel)}`,
        );
      },
    ],
    [
      "has a provider name",
      () => {
        expect(
          typeof transport.provider === "string" && transport.provider !== "",
          "provider must be a non-empty string",
        );
      },
    ],
    [
      "sends a message without mutating it and returns a valid receipt",
      async () => {
        const receipt = await transport.send(message, { idempotencyKey: KEY });

        if (receipt === undefined) {
          return;
        }

        expect(
          receipt.providerMessageId === undefined ||
            typeof receipt.providerMessageId === "string",
          "providerMessageId must be a string",
        );
      },
    ],
    options.received && [
      "passes the idempotency key and the headers to the provider",
      async () => {
        const all = await options.received!();
        const found = all.find((entry) => entry.idempotencyKey === KEY);
        expect(found, `no message arrived with idempotency key ${KEY}`);

        for (const [name, value] of Object.entries(message.headers)) {
          expect(
            found.headers[name] === value,
            `header ${name} must be "${value}", got ${String(found.headers[name])}`,
          );
        }
      },
    ],
  ]);
}
