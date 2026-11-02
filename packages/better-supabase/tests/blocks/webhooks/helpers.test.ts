import { describe, expect, it } from "vitest";

import { createWebhooks } from "../../../src/blocks/webhooks/index.ts";

function setup(rotate: (() => Promise<string>) | undefined) {
  const calls: [string, Record<string, unknown>][] = [];

  const webhooks = createWebhooks({
    transport: {
      call(_schema: string, fn: string, args: Record<string, unknown>) {
        calls.push([fn, args]);

        return Promise.resolve(
          fn === "delete_webhook_endpoint"
            ? null
            : { id: "e1", url: "https://example.com/hook", enabled: true },
        );
      },
    },
    secrets: {
      apiVersion: 1,
      secrets: async () => [],
      ...(rotate === undefined ? {} : { rotate }),
    },
  });

  return { webhooks, calls };
}

describe("webhooks helpers", () => {
  it("createEndpoint with withSecret returns the endpoint with its secret", async () => {
    const { webhooks } = setup(async () => "whsec_new");

    const created = await webhooks
      .createEndpoint({
        tenant: "o",
        url: "https://example.com/hook",
        eventTypes: [],
        withSecret: true,
      })
      .orThrow();

    expect(created).toMatchObject({ id: "e1", secret: "whsec_new" });
  });

  it("deletes the endpoint again when the secret can't be created", async () => {
    const { webhooks, calls } = setup(undefined);

    const created = await webhooks.createEndpoint({
      tenant: "o",
      url: "https://example.com/hook",
      eventTypes: [],
      withSecret: true,
    });

    expect(created.ok).toBe(false);
    expect(calls.map(([fn]) => fn)).toEqual([
      "create_webhook_endpoint",
      "delete_webhook_endpoint",
    ]);
  });

  it("setEnabled updates only the enabled flag", async () => {
    const { webhooks, calls } = setup(undefined);

    await webhooks.setEnabled({ endpointId: "e1", enabled: false }).orThrow();

    expect(calls[0]).toEqual([
      "update_webhook_endpoint",
      { endpoint: "e1", fields: { enabled: false } },
    ]);
  });
});
