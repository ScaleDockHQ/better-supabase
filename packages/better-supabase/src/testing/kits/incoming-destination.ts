import type {
  IncomingDelivery,
  IncomingDestination,
} from "../../blocks/webhooks/incoming-types.ts";

import { conform, expect, type ConformanceReport } from "../conformance.ts";
import { hasName } from "./executor.ts";

export interface TestIncomingDestinationOptions {
  /** The tenant the test deliveries belong to. */
  readonly tenant: string;
  /** Defaults to `conformance`. */
  readonly source?: string;
}

/**
 * Proves an `IncomingDestination` accepts a delivery once per endpoint and
 * message id: a repeat reports the first id as a duplicate, while another
 * message id or another endpoint is new. It delivers four messages with random
 * endpoint ids; the destination keeps them.
 */
export function testIncomingDestination(
  destination: IncomingDestination,
  options: TestIncomingDestinationOptions,
): Promise<ConformanceReport> {
  const endpoint = crypto.randomUUID();

  const delivery = (
    messageId: string,
    endpointId = endpoint,
  ): IncomingDelivery => ({
    endpoint: { id: endpointId, tenant: options.tenant, metadata: {} },
    source: options.source ?? "conformance",
    messageId,
    type: "conformance.test",
    payload: { type: "conformance.test", messageId },
    headers: {},
  });

  return conform(`IncomingDestination "${destination.name}"`, [
    hasName(destination),
    [
      "has apiVersion 1",
      () => {
        const version: unknown = destination.apiVersion;
        expect(version === 1, "apiVersion must be 1");
      },
    ],
    [
      "reports a repeated endpoint and message id as a duplicate of the first",
      async () => {
        const first = await destination.deliver(delivery("m1"));
        expect(!first.duplicate, "the first delivery must not be a duplicate");
        const again = await destination.deliver(delivery("m1"));
        expect(again.duplicate, "a repeated delivery must be a duplicate");
        expect(
          String(again.id) === String(first.id),
          "a duplicate must return the first delivery's id",
        );
      },
    ],
    [
      "treats another message id or another endpoint as a new delivery",
      async () => {
        const other = await destination.deliver(delivery("m2"));
        expect(!other.duplicate, "another message id must be new");

        const elsewhere = await destination.deliver(
          delivery("m1", crypto.randomUUID()),
        );

        expect(
          !elsewhere.duplicate,
          "the same id on another endpoint must be new",
        );
      },
    ],
  ]);
}
