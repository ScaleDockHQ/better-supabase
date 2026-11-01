import { describe, expect, it } from "vitest";

import type { AgentCheckoutOptions } from "../../../src/blocks/agent-checkout/index.ts";

import {
  agentCheckoutBlock,
  checkoutHash,
  createAgentCheckout,
} from "../../../src/blocks/agent-checkout/index.ts";
import { money } from "../../../src/commerce/money.ts";
import {
  generateSigningKey,
  importSigningKey,
  signCompact,
} from "../../../src/core/jws.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const SESSION = {
  id: "s1",
  organizationId: "org-1",
  cartId: "cart-1",
  protocol: "acp",
  status: "ready",
  expired: false,
  createdAt: AT,
  updatedAt: AT,
};

const OWNER = { kind: "organization", id: "org-1" } as const;

async function signing() {
  const { kid, publicKey, privateKey } = await generateSigningKey("ES256");
  const key = await importSigningKey(privateKey);

  const keys = {
    jwks: () => AsyncResult.ok({ keys: [{ ...publicKey, kid, alg: "ES256" }] }),
    signer: () => ({
      signJwt: (claims: Record<string, unknown>) =>
        AsyncResult.from(async () => ({
          ok: true as const,
          data: await signCompact(
            key,
            "ES256",
            { alg: "ES256", kid, typ: "JWT" },
            claims,
          ),
          error: null,
        })),
    }),
  };

  // SAFETY: the test double implements the two methods the block calls.
  return { keys, owner: OWNER } as unknown as NonNullable<
    AgentCheckoutOptions["signing"]
  >;
}

const orders = (total = money(5000n, "EUR"), problems: unknown[] = []) =>
  // SAFETY: the test double implements the two methods the block calls.
  ({
    priceCart: () => AsyncResult.ok({ total, problems }),
    checkout: () =>
      AsyncResult.ok({ order: { id: "o1" }, payment: { id: "p1" } }),
  }) as unknown as NonNullable<AgentCheckoutOptions["orders"]>;

describe("createAgentCheckout", () => {
  it("creates a session and reports an idempotent replay", async () => {
    const t = fieldsTransport({
      create_checkout_session: () => ({ ...SESSION, replayed: true }),
    });

    const checkout = createAgentCheckout({ transport: t, tenant: "org-1" });

    const session = await checkout
      .createSession({
        cartId: "cart-1",
        protocol: "acp",
        idempotencyKey: "k1",
      })
      .orThrow();

    expect(session).toMatchObject({
      id: "s1",
      protocol: "acp",
      replayed: true,
    });
    expect(t.calls[0]?.[1]).toMatchObject({
      tenant: "org-1",
      cart_id: "cart-1",
      protocol: "acp",
      idempotency_key: "k1",
    });
    expect(typeof t.calls[0]?.[1]["request_hash"]).toBe("string");
  });

  it("asks for orders and signing instead of failing late", async () => {
    const checkout = createAgentCheckout({
      transport: fieldsTransport({}),
      tenant: "org-1",
    });

    const priced = await checkout.priceSession("s1");

    const signed = await checkout.signMandate({
      kind: "open",
      subject: "u1",
      maxTotal: money(100n, "EUR"),
      expiresAt: Temporal.Now.instant().add({ hours: 1 }),
    });

    expect(priced.ok).toBe(false);
    expect(priced.error?.hint).toBe("AGENT_CHECKOUT_NOT_CONFIGURED");
    expect(signed.error?.hint).toBe("AGENT_CHECKOUT_NOT_CONFIGURED");
  });

  it("signs an open mandate and verifies it against the JWKS", async () => {
    const checkout = createAgentCheckout({
      transport: fieldsTransport({}),
      tenant: "org-1",
      signing: await signing(),
    });

    const credential = await checkout
      .signMandate({
        kind: "open",
        subject: "u1",
        maxTotal: money(7500n, "EUR"),
        expiresAt: Temporal.Now.instant().add({ hours: 1 }),
      })
      .orThrow();

    const verified = await checkout.verifyMandate(credential).orThrow();

    expect(verified).toMatchObject({
      kind: "open",
      vct: "mandate.checkout.open.1",
      subject: "u1",
      maxTotal: money(7500n, "EUR"),
    });

    const [header, payload, signature] = credential.split(".");
    const tampered = `${header}.${payload}x.${signature}`;

    expect((await checkout.verifyMandate(tampered)).ok).toBe(false);
  });

  it("binds a closed mandate to the cart and its priced total", async () => {
    const t = fieldsTransport({ get_checkout_session: () => SESSION });

    const checkout = createAgentCheckout({
      transport: t,
      tenant: "org-1",
      orders: orders(),
      signing: await signing(),
    });

    const credential = await checkout
      .signMandate({
        kind: "closed",
        subject: "u1",
        sessionId: "s1",
        expiresAt: Temporal.Now.instant().add({ hours: 1 }),
      })
      .orThrow();

    const verified = await checkout.verifyMandate(credential).orThrow();

    expect(verified.kind).toBe("closed");
    expect(verified.sessionId).toBe("s1");
    expect(verified.checkoutHash).toBe(
      await checkoutHash("cart-1", money(5000n, "EUR")),
    );
    expect(await checkoutHash("cart-1", money(5001n, "EUR"))).not.toBe(
      verified.checkoutHash,
    );
  });

  it("refuses to complete a session that is not ready", async () => {
    const t = fieldsTransport({
      get_checkout_session: () => ({ ...SESSION, status: "open" }),
    });

    const checkout = createAgentCheckout({
      transport: t,
      tenant: "org-1",
      orders: orders(),
    });

    const result = await checkout.completeSession("s1");

    expect(result.ok).toBe(false);
    expect(t.calls.map(([fn]) => fn)).toEqual(["get_checkout_session"]);
  });

  it("refuses a ready session without a mandate when mandates are required", async () => {
    const t = fieldsTransport({ get_checkout_session: () => SESSION });

    const checkout = createAgentCheckout({
      transport: t,
      tenant: "org-1",
      orders: orders(),
      mandates: "required",
      signing: await signing(),
    });

    const result = await checkout.completeSession("s1");

    expect(result.ok).toBe(false);
    expect(t.calls.map(([fn]) => fn)).not.toContain(
      "complete_checkout_session",
    );
  });

  it("is a block that needs no fields", () => {
    expect(agentCheckoutBlock.name).toBe("agent-checkout");
  });
});
