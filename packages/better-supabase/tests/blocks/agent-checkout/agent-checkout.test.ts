import { describe, expect, it } from "vitest";

import type { AgentCheckoutOptions } from "../../../src/blocks/agent-checkout/index.ts";

import {
  agentCheckoutBlock,
  checkoutHash,
  createAgentCheckout,
} from "../../../src/blocks/agent-checkout/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { dbError } from "../../../src/core/errors.ts";
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

    const result = await checkout.completeSession({ sessionId: "s1" });

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

    const result = await checkout.completeSession({ sessionId: "s1" });

    expect(result.ok).toBe(false);
    expect(t.calls.map(([fn]) => fn)).not.toContain(
      "complete_checkout_session",
    );
  });

  it("is a block that needs no fields", () => {
    expect(agentCheckoutBlock.name).toBe("agent-checkout");
  });
});

const MANDATE = {
  id: "m1",
  organizationId: "org-1",
  vct: "mandate.checkout.open.1",
  status: "active",
  credential: "c",
  credentialHash: "h",
  expiresAt: AT,
  expired: false,
  createdAt: AT,
};

const FAIL = () => {
  throw new Error("boom");
};

async function minter() {
  const { kid, publicKey, privateKey } = await generateSigningKey("ES256");
  const key = await importSigningKey(privateKey);

  const keys = {
    jwks: () => AsyncResult.ok({ keys: [{ ...publicKey, kid, alg: "ES256" }] }),
    signer: () => ({}),
  };

  // SAFETY: the test double implements the methods the block calls.
  const options = { keys, owner: OWNER } as unknown as NonNullable<
    AgentCheckoutOptions["signing"]
  >;

  const mint = (claims: Record<string, unknown>) =>
    signCompact(key, "ES256", { alg: "ES256", kid, typ: "JWT" }, claims);

  return { options, mint };
}

const future = () => Math.floor(Date.now() / 1000) + 3600;

const OPEN_CLAIMS = {
  vct: "mandate.checkout.open.1",
  sub: "u1",
  max_total: { amount: "6000", currency: "EUR" },
};

describe("createAgentCheckout reads and writes", () => {
  it("maps sessions with every optional column", async () => {
    const full = {
      ...SESSION,
      buyer: { name: "Ada" },
      orderId: "o1",
      expiresAt: AT,
      createdBy: "u1",
    };

    const t = fieldsTransport({
      get_checkout_session: () => full,
      list_checkout_sessions: () => [full, SESSION],
      update_checkout_session: () => full,
    });

    const checkout = createAgentCheckout({ transport: t, tenant: "org-1" });
    const got = await checkout.getSession("s1").orThrow();

    expect(got.buyer).toEqual({ name: "Ada" });
    expect(got.orderId).toBe("o1");
    expect(got.createdBy).toBe("u1");
    expect(got.expiresAt?.toString()).toBe("2026-10-29T10:00:00Z");

    const listed = await checkout
      .listSessions({ status: "ready", cartId: "cart-1", limit: 5 })
      .orThrow();

    expect(listed).toHaveLength(2);
    expect(t.calls.at(-1)?.[1]).toMatchObject({
      tenant: "org-1",
      filters: { status: "ready", cartId: "cart-1", limit: 5 },
    });

    await checkout.listSessions().orThrow();
    expect(t.calls.at(-1)?.[1]["filters"]).toEqual({});

    const expiresAt = Temporal.Instant.from(AT);

    await checkout
      .updateSession({
        sessionId: "s1",
        buyer: null,
        status: "ready",
        expiresAt,
      })
      .orThrow();
    expect(t.calls.at(-1)?.[1]["input"]).toMatchObject({
      buyer: null,
      status: "ready",
    });

    await checkout
      .updateSession({ sessionId: "s1", expiresAt: null })
      .orThrow();
    expect(t.calls.at(-1)?.[1]["input"]).toEqual({ expiresAt: null });

    await checkout.cancelSession("s1").orThrow();
    expect(t.calls.at(-1)?.[1]["input"]).toEqual({ status: "canceled" });
  });

  it("returns errors for malformed rows and failing calls", async () => {
    const t = fieldsTransport({
      get_checkout_session: () => ({ ...SESSION, protocol: "nope" }),
      list_checkout_sessions: () => "nope",
      create_checkout_session: () => ({ ...SESSION, status: "weird" }),
      update_checkout_session: () => null,
      get_agent_mandate: () => ({ ...MANDATE, vct: "x" }),
      list_agent_mandates: () => [{ ...MANDATE, status: "x" }],
      revoke_agent_mandate: FAIL,
    });

    const checkout = createAgentCheckout({ transport: t, tenant: "org-1" });

    expect((await checkout.getSession("s1")).ok).toBe(false);
    expect((await checkout.listSessions()).ok).toBe(false);
    expect(
      (
        await checkout.createSession({
          cartId: "c",
          protocol: "ucp",
          idempotencyKey: "k",
        })
      ).ok,
    ).toBe(false);
    expect((await checkout.updateSession({ sessionId: "s1" })).ok).toBe(false);
    expect((await checkout.getMandate("m1")).ok).toBe(false);
    expect((await checkout.listMandates()).ok).toBe(false);
    expect((await checkout.revokeMandate("m1")).ok).toBe(false);
  });

  it("needs a tenant to create and list", async () => {
    const checkout = createAgentCheckout({ transport: fieldsTransport({}) });

    const created = await checkout.createSession({
      cartId: "c",
      protocol: "acp",
      idempotencyKey: "k",
    });

    expect(created.ok).toBe(false);
    expect((await checkout.listSessions()).ok).toBe(false);
    expect((await checkout.listMandates()).ok).toBe(false);
    expect((await checkout.storeMandate({ credential: "x" })).ok).toBe(false);
  });

  it("reads, lists and revokes mandates", async () => {
    const full = {
      ...MANDATE,
      sessionId: "s1",
      issuerKid: "k",
      subject: "u1",
      consumedAt: AT,
      createdBy: "u1",
      expired: true,
    };

    const t = fieldsTransport({
      get_agent_mandate: () => full,
      list_agent_mandates: () => [full, MANDATE],
      revoke_agent_mandate: () => true,
    });

    const checkout = createAgentCheckout({ transport: t, tenant: "org-1" });
    const got = await checkout.getMandate("m1").orThrow();

    expect(got).toMatchObject({
      sessionId: "s1",
      issuerKid: "k",
      subject: "u1",
      expired: true,
    });

    const listed = await checkout
      .listMandates({ sessionId: "s1", status: "active" })
      .orThrow();

    expect(listed).toHaveLength(2);
    expect(await checkout.revokeMandate("m1").orThrow()).toBe(true);
  });

  it("rejects mandates with wrong claims", async () => {
    const { options, mint } = await minter();

    const checkout = createAgentCheckout({
      transport: fieldsTransport({}),
      tenant: "org-1",
      signing: options,
    });

    const hint = async (claims: Record<string, unknown>) =>
      (await checkout.verifyMandate(await mint(claims))).error?.hint;

    expect(await hint({ ...OPEN_CLAIMS, vct: "x", exp: future() })).toBe(
      "AGENT_MANDATE_INVALID",
    );
    expect(await hint({ ...OPEN_CLAIMS, sub: "", exp: future() })).toBe(
      "AGENT_MANDATE_INVALID",
    );
    expect(await hint({ ...OPEN_CLAIMS })).toBe("AGENT_MANDATE_INVALID");
    expect(await hint({ ...OPEN_CLAIMS, exp: 1 })).toBe(
      "AGENT_MANDATE_EXPIRED",
    );
    expect(await hint({ ...OPEN_CLAIMS, max_total: "x", exp: future() })).toBe(
      "AGENT_MANDATE_INVALID",
    );
    expect(
      await hint({
        ...OPEN_CLAIMS,
        max_total: { amount: "-1", currency: "EUR" },
        exp: future(),
      }),
    ).toBe("AGENT_MANDATE_INVALID");
    expect(
      await hint({
        vct: "mandate.checkout.1",
        sub: "u1",
        exp: future(),
        session_id: "s1",
      }),
    ).toBe("AGENT_MANDATE_INVALID");
    expect((await checkout.verifyMandate("garbage")).error?.hint).toBe(
      "AGENT_MANDATE_INVALID",
    );
  });

  it("stores a verified mandate and refuses an invalid one", async () => {
    const { options, mint } = await minter();

    const t = fieldsTransport({ store_agent_mandate: () => MANDATE });

    const checkout = createAgentCheckout({
      transport: t,
      tenant: "org-1",
      signing: options,
    });

    const credential = await mint({ ...OPEN_CLAIMS, exp: future() });

    const stored = await checkout
      .storeMandate({ credential, sessionId: "s1" })
      .orThrow();

    expect(stored.id).toBe("m1");
    expect(t.calls[0]?.[1]["input"]).toMatchObject({
      vct: "mandate.checkout.open.1",
      credential,
      sessionId: "s1",
    });
    expect((await checkout.storeMandate({ credential: "garbage" })).ok).toBe(
      false,
    );
  });

  it("fails signing when the JWKS cannot be read", async () => {
    const { options } = await minter();

    const checkout = createAgentCheckout({
      transport: fieldsTransport({}),
      tenant: "org-1",
      signing: {
        ...options,
        keys: {
          ...options.keys,
          jwks: () => AsyncResult.err(dbError("unexpected", "no jwks")),
        },
      },
    });

    expect((await checkout.verifyMandate("a.b.c")).ok).toBe(false);
  });

  it("reports price problems and lookup failures", async () => {
    const failing = fieldsTransport({ get_checkout_session: FAIL });

    const base = { tenant: "org-1", orders: orders() };

    expect(
      (
        await createAgentCheckout({ ...base, transport: failing }).priceSession(
          "s",
        )
      ).ok,
    ).toBe(false);

    const t = fieldsTransport({ get_checkout_session: () => SESSION });

    const problems = createAgentCheckout({
      transport: t,
      tenant: "org-1",
      orders: orders(money(1n, "EUR"), [{ code: "x" }]),
    });

    expect((await problems.priceSession("s1")).error?.hint).toBe(
      "CHECKOUT_CART_NOT_READY",
    );

    const cartFails = createAgentCheckout({
      transport: t,
      tenant: "org-1",
      orders: {
        priceCart: () => AsyncResult.err(dbError("not_found", "no cart")),
        checkout: () => AsyncResult.err(dbError("unexpected", "x")),
      },
    });

    expect((await cartFails.priceSession("s1")).ok).toBe(false);

    const closed = createAgentCheckout({
      transport: failing,
      tenant: "org-1",
      orders: orders(),
      signing: (await minter()).options,
    });

    const signed = await closed.signMandate({
      kind: "closed",
      subject: "u1",
      sessionId: "s1",
      expiresAt: Temporal.Now.instant().add({ hours: 1 }),
    });

    expect(signed.ok).toBe(false);
  });

  it("completes only sessions in a completable state", async () => {
    const run = (row: Record<string, unknown>) =>
      createAgentCheckout({
        transport: fieldsTransport({ get_checkout_session: () => row }),
        tenant: "org-1",
        orders: orders(),
      }).completeSession({ sessionId: "s1" });

    const done = await run({ ...SESSION, status: "completed" });

    expect(done.ok && done.data.payment).toBeNull();
    expect((await run({ ...SESSION, status: "canceled" })).error?.hint).toBe(
      "CHECKOUT_SESSION_FINAL",
    );
    expect((await run({ ...SESSION, expired: true })).error?.hint).toBe(
      "CHECKOUT_SESSION_EXPIRED",
    );
    expect((await run({ ...SESSION, status: "open" })).error?.hint).toBe(
      "CHECKOUT_NOT_READY",
    );

    const noOrders = createAgentCheckout({
      transport: fieldsTransport({}),
      tenant: "org-1",
    });

    expect(
      (await noOrders.completeSession({ sessionId: "s1" })).error?.hint,
    ).toBe("AGENT_CHECKOUT_NOT_CONFIGURED");

    const failing = createAgentCheckout({
      transport: fieldsTransport({ get_checkout_session: FAIL }),
      tenant: "org-1",
      orders: orders(),
    });

    expect((await failing.completeSession({ sessionId: "s1" })).ok).toBe(false);

    const unpriced = createAgentCheckout({
      transport: fieldsTransport({ get_checkout_session: () => SESSION }),
      tenant: "org-1",
      orders: orders(money(1n, "EUR"), [{ code: "x" }]),
    });

    expect((await unpriced.completeSession({ sessionId: "s1" })).ok).toBe(
      false,
    );
  });

  it("completes without a mandate when they are optional", async () => {
    const t = fieldsTransport({
      get_checkout_session: () => SESSION,
      complete_checkout_session: () => ({
        ...SESSION,
        status: "completed",
        orderId: "o1",
      }),
    });

    const checkout = createAgentCheckout({
      transport: t,
      tenant: "org-1",
      orders: orders(),
    });

    const result = await checkout
      .completeSession({ sessionId: "s1" })
      .orThrow();

    expect(result.session.status).toBe("completed");
    expect(result.payment).toMatchObject({ id: "p1" });
    expect(result.mandate).toBeUndefined();
  });

  it("completes under an open mandate and enforces its limit", async () => {
    const { options, mint } = await minter();

    const t = fieldsTransport({
      get_checkout_session: () => SESSION,
      store_agent_mandate: () => MANDATE,
      complete_checkout_session: () => ({ ...SESSION, status: "completed" }),
    });

    const make = (total: ReturnType<typeof money>) =>
      createAgentCheckout({
        transport: t,
        tenant: "org-1",
        orders: orders(total),
        signing: options,
      });

    const credential = await mint({ ...OPEN_CLAIMS, exp: future() });

    const ok = await make(money(5000n, "EUR"))
      .completeSession({ sessionId: "s1", mandate: credential })
      .orThrow();

    expect(ok.mandate?.id).toBe("m1");

    for (const total of [money(7000n, "EUR"), money(100n, "USD")]) {
      const refused = await make(total).completeSession({
        sessionId: "s1",
        mandate: credential,
      });

      expect(refused.error?.hint).toBe("AGENT_MANDATE_LIMIT");
    }

    const bad = await make(money(1n, "EUR")).completeSession({
      sessionId: "s1",
      mandate: "garbage",
    });

    expect(bad.ok).toBe(false);
  });

  it("consumes a closed mandate before the checkout", async () => {
    const { options, mint } = await minter();
    const total = money(5000n, "EUR");

    const closedClaims = async (sessionId: string, cartId = "cart-1") => ({
      vct: "mandate.checkout.1",
      sub: "u1",
      exp: future(),
      session_id: sessionId,
      checkout_hash: await checkoutHash(cartId, total),
    });

    const results: Record<string, () => unknown> = {
      get_checkout_session: () => SESSION,
      store_agent_mandate: () => ({ ...MANDATE, vct: "mandate.checkout.1" }),
      consume_agent_mandate: () => ({ ...MANDATE, status: "consumed" }),
      complete_checkout_session: () => ({ ...SESSION, status: "completed" }),
    };

    const make = (overrides: Record<string, () => unknown> = {}) => {
      const t = fieldsTransport({ ...results, ...overrides });

      return {
        t,
        checkout: createAgentCheckout({
          transport: t,
          tenant: "org-1",
          orders: orders(total),
          signing: options,
        }),
      };
    };

    const good = await mint(await closedClaims("s1"));
    const happy = make();

    const done = await happy.checkout
      .completeSession({ sessionId: "s1", mandate: good })
      .orThrow();

    expect(done.mandate?.status).toBe("consumed");
    expect(happy.t.calls.map(([fn]) => fn)).toContain("consume_agent_mandate");

    const other = await mint(await closedClaims("s2"));

    expect(
      (
        await make().checkout.completeSession({
          sessionId: "s1",
          mandate: other,
        })
      ).error?.hint,
    ).toBe("AGENT_MANDATE_MISMATCH");

    const stale = await mint(await closedClaims("s1", "cart-2"));

    expect(
      (
        await make().checkout.completeSession({
          sessionId: "s1",
          mandate: stale,
        })
      ).error?.hint,
    ).toBe("AGENT_MANDATE_MISMATCH");

    expect(
      (
        await make({ store_agent_mandate: FAIL }).checkout.completeSession({
          sessionId: "s1",
          mandate: good,
        })
      ).ok,
    ).toBe(false);
    expect(
      (
        await make({ consume_agent_mandate: FAIL }).checkout.completeSession({
          sessionId: "s1",
          mandate: good,
        })
      ).ok,
    ).toBe(false);
    expect(
      (
        await make({
          complete_checkout_session: FAIL,
        }).checkout.completeSession({ sessionId: "s1" })
      ).ok,
    ).toBe(false);
  });

  it("returns the orders checkout error", async () => {
    const checkout = createAgentCheckout({
      transport: fieldsTransport({ get_checkout_session: () => SESSION }),
      tenant: "org-1",
      // SAFETY: the test double implements the methods the block calls.
      orders: {
        priceCart: () =>
          AsyncResult.ok({ total: money(1n, "EUR"), problems: [] }),
        checkout: () => AsyncResult.err(dbError("unexpected", "declined")),
      } as unknown as NonNullable<AgentCheckoutOptions["orders"]>,
    });

    expect((await checkout.completeSession({ sessionId: "s1" })).ok).toBe(
      false,
    );
  });
});
