import { describe, expect, it } from "vitest";

import { createLedger, ledgerMoney } from "../../../src/blocks/ledger/index.ts";
import { ledgerBinding } from "../../../src/blocks/ledger/record-binding.ts";
import { money } from "../../../src/commerce/money.ts";

const AT = "2026-10-22T10:00:00Z";

const ACCOUNT = {
  id: "a1",
  organizationId: "org-1",
  kind: "credit",
  code: "credit:p1",
  name: "Credits",
  unit: "EUR",
  scale: 0,
  holderType: "party",
  holderId: "p1",
  ownerId: null,
  allowNegative: false,
  readPermission: "parties.read",
  managedBy: null,
  metadata: { tier: "gold" },
  closedAt: null,
  createdAt: AT,
  balance: "1500",
  held: "500",
  available: "1000",
};

const TRANSACTION = {
  id: "t1",
  organizationId: "org-1",
  kind: "credit.grant",
  referenceType: "orders",
  referenceId: "o1",
  memo: "welcome",
  idempotencyKey: "k1",
  reverses: null,
  metadata: null,
  effectiveAt: AT,
  actorId: "u1",
  createdAt: AT,
  entries: [
    { id: "e1", accountId: "a1", amount: "1500", unit: "EUR" },
    { id: "e2", accountId: "a2", amount: "-1500", unit: "EUR" },
  ],
};

const HOLD = {
  id: "h1",
  organizationId: "org-1",
  accountId: "a1",
  amount: "500",
  status: "active",
  referenceType: "orders",
  referenceId: "o2",
  expiresAt: AT,
  transactionId: null,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const ENTRY = {
  id: "e1",
  accountId: "a1",
  amount: "1500",
  unit: "EUR",
  transactionId: "t1",
  kind: "credit.grant",
  referenceType: null,
  referenceId: null,
  memo: null,
  reverses: null,
  metadata: {},
  effectiveAt: AT,
  actorId: "u1",
  createdAt: AT,
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

describe("createLedger", () => {
  it("opens and lists accounts in the block's tenant", async () => {
    const fake = fakeTransport({
      open_ledger_account: ACCOUNT,
      list_ledger_accounts: [ACCOUNT],
    });

    const ledger = createLedger({ transport: fake.transport, tenant: "org-1" });

    const account = await ledger
      .openAccount({
        kind: "credit",
        code: "credit:p1",
        name: "Credits",
        unit: "EUR",
        holder: { type: "party", id: "p1" },
        readPermission: "parties.read",
        metadata: { tier: "gold" },
      })
      .orThrow();

    expect(account).toMatchObject({
      id: "a1",
      balance: 1500n,
      held: 500n,
      available: 1000n,
      holderType: "party",
      readPermission: "parties.read",
      metadata: { tier: "gold" },
    });
    expect(account.ownerId).toBeUndefined();
    expect(account.createdAt.toString()).toBe("2026-10-22T10:00:00Z");

    await ledger.accounts({ kind: "credit" }).orThrow();
    await ledger.holderAccounts({ type: "party", id: "p1" }).orThrow();

    expect(fake.calls).toEqual([
      [
        "open_ledger_account",
        {
          tenant: "org-1",
          kind: "credit",
          code: "credit:p1",
          name: "Credits",
          unit: "EUR",
          scale: 0,
          holder_type: "party",
          holder_id: "p1",
          owner_id: null,
          allow_negative: false,
          read_permission: "parties.read",
          metadata: { tier: "gold" },
        },
      ],
      [
        "list_ledger_accounts",
        {
          tenant: "org-1",
          kind: "credit",
          holder_type: null,
          holder_id: null,
          page_size: null,
        },
      ],
      [
        "list_ledger_accounts",
        {
          tenant: null,
          kind: null,
          holder_type: "party",
          holder_id: "p1",
          page_size: null,
        },
      ],
    ]);
  });

  it("fails without a tenant", async () => {
    const fake = fakeTransport({});
    const ledger = createLedger({ transport: fake.transport });

    expect(await ledger.accounts()).toMatchObject({
      ok: false,
      error: { kind: "invalid_request", hint: "TENANT_REQUIRED" },
    });
    expect(fake.calls).toEqual([]);
  });

  it("posts lines in bigint or Money and reads the transaction back", async () => {
    const fake = fakeTransport({
      post_ledger_transaction: TRANSACTION,
      reverse_ledger_transaction: { ...TRANSACTION, id: "t2", reverses: "t1" },
      get_ledger_transaction: TRANSACTION,
      close_ledger_account: { ...ACCOUNT, closedAt: AT, balance: "0" },
    });

    const ledger = createLedger({ transport: fake.transport, tenant: "org-1" });

    const posted = await ledger
      .post({
        kind: "credit.grant",
        lines: [
          { accountId: "a1", amount: money(1500n, "EUR") },
          { accountId: "a2", amount: -1500n },
        ],
        reference: { type: "orders", id: "o1" },
        memo: "welcome",
        idempotencyKey: "k1",
        effectiveAt: Temporal.Instant.from(AT),
        metadata: { source: "signup" },
      })
      .orThrow();

    expect(posted).toMatchObject({
      id: "t1",
      referenceType: "orders",
      idempotencyKey: "k1",
      actorId: "u1",
      metadata: {},
      entries: [
        { id: "e1", amount: 1500n },
        { id: "e2", amount: -1500n },
      ],
    });
    expect(posted.reverses).toBeUndefined();

    expect(
      (await ledger.reverse("t1", { memo: "undo" }).orThrow()).reverses,
    ).toBe("t1");
    expect((await ledger.transaction("t1").orThrow()).kind).toBe(
      "credit.grant",
    );
    expect(
      (await ledger.closeAccount("a1").orThrow()).closedAt?.toString(),
    ).toBe("2026-10-22T10:00:00Z");

    expect(fake.calls[0]).toEqual([
      "post_ledger_transaction",
      {
        tenant: "org-1",
        kind: "credit.grant",
        lines: [
          { account: "a1", amount: "1500" },
          { account: "a2", amount: "-1500" },
        ],
        reference_type: "orders",
        reference_id: "o1",
        memo: "welcome",
        idempotency_key: "k1",
        effective_at: "2026-10-22T10:00:00Z",
        metadata: { source: "signup" },
      },
    ]);
    expect(fake.calls.slice(1)).toEqual([
      ["reverse_ledger_transaction", { transaction_id: "t1", memo: "undo" }],
      ["get_ledger_transaction", { transaction_id: "t1" }],
      ["close_ledger_account", { account_id: "a1" }],
    ]);
  });

  it("pages an account's entries", async () => {
    const fake = fakeTransport({ ledger_account_entries: [ENTRY] });
    const ledger = createLedger({ transport: fake.transport });

    const [entry] = await ledger
      .entries("a1", { before: Temporal.Instant.from(AT), pageSize: 10 })
      .orThrow();

    expect(entry).toMatchObject({
      transactionId: "t1",
      amount: 1500n,
      kind: "credit.grant",
      actorId: "u1",
    });
    expect(entry?.memo).toBeUndefined();
    await ledger.entries("a1").orThrow();
    expect(fake.calls).toEqual([
      [
        "ledger_account_entries",
        { account_id: "a1", before: "2026-10-22T10:00:00Z", page_size: 10 },
      ],
      [
        "ledger_account_entries",
        { account_id: "a1", before: undefined, page_size: null },
      ],
    ]);
  });

  it("places, captures and releases holds", async () => {
    const fake = fakeTransport({
      place_ledger_hold: HOLD,
      capture_ledger_hold: { ...HOLD, status: "captured", transactionId: "t3" },
      release_ledger_hold: {
        ...HOLD,
        status: "released",
        referenceType: null,
        referenceId: null,
        expiresAt: null,
        createdBy: null,
      },
    });

    const ledger = createLedger({ transport: fake.transport });

    const hold = await ledger
      .hold("a1", {
        amount: money(500n, "EUR"),
        reference: { type: "orders", id: "o2" },
        expiresAt: Temporal.Instant.from(AT),
      })
      .orThrow();

    expect(hold).toMatchObject({ amount: 500n, status: "active" });
    expect(hold.expiresAt?.toString()).toBe("2026-10-22T10:00:00Z");

    const captured = await ledger
      .capture("h1", { toAccountId: "a3", amount: 200n, memo: "order" })
      .orThrow();

    expect(captured.transactionId).toBe("t3");
    await ledger.capture("h1", { toAccountId: "a3", kind: "order.capture" });

    const released = await ledger.release("h1").orThrow();
    expect(released.status).toBe("released");
    expect(released.expiresAt).toBeUndefined();

    expect(fake.calls).toEqual([
      [
        "place_ledger_hold",
        {
          account_id: "a1",
          amount: "500",
          reference_type: "orders",
          reference_id: "o2",
          expires_at: "2026-10-22T10:00:00Z",
        },
      ],
      [
        "capture_ledger_hold",
        {
          hold_id: "h1",
          to_account: "a3",
          amount: "200",
          kind: "ledger.capture",
          memo: "order",
        },
      ],
      [
        "capture_ledger_hold",
        {
          hold_id: "h1",
          to_account: "a3",
          amount: null,
          kind: "order.capture",
          memo: null,
        },
      ],
      ["release_ledger_hold", { hold_id: "h1" }],
    ]);
  });

  it("rejects a hold status it doesn't know", async () => {
    const fake = fakeTransport({
      release_ledger_hold: { ...HOLD, status: "lost" },
    });

    const ledger = createLedger({ transport: fake.transport });

    expect((await ledger.release("h1")).ok).toBe(false);
  });

  it("passes every optional argument through", async () => {
    const fake = fakeTransport({
      open_ledger_account: { ...ACCOUNT, scale: null, allowNegative: true },
      list_ledger_accounts: [ACCOUNT],
      post_ledger_transaction: TRANSACTION,
      place_ledger_hold: HOLD,
      capture_ledger_hold: { ...HOLD, status: "captured" },
    });

    const ledger = createLedger({
      transport: fake.transport,
      tenant: "org-1",
      logger: { debug() {}, info() {}, warn() {}, error() {} },
    });

    const at = Temporal.Instant.from(AT);

    const account = await ledger
      .openAccount({
        kind: "points",
        code: "points:p1",
        name: "Points",
        unit: "points",
        scale: 2,
        holder: { type: "party", id: "p1" },
        ownerId: "u1",
        allowNegative: true,
        readPermission: "parties.read",
        metadata: { tier: "gold" },
      })
      .orThrow();

    await ledger
      .accounts({ kind: "credit", holder: { type: "party", id: "p1" } })
      .orThrow();
    await ledger
      .post({
        kind: "credit.grant",
        lines: [
          { accountId: "a1", amount: 100n },
          { accountId: "a2", amount: money(-100n, "EUR") },
        ],
        reference: { type: "orders", id: "o1" },
        memo: "welcome",
        idempotencyKey: "k1",
        effectiveAt: at,
        metadata: { source: "signup" },
      })
      .orThrow();
    await ledger
      .hold("a1", {
        amount: 500n,
        reference: { type: "orders", id: "o2" },
        expiresAt: at,
      })
      .orThrow();
    await ledger
      .capture("h1", {
        toAccountId: "a2",
        amount: 200n,
        kind: "gift_card.redeem",
        memo: "order o2",
      })
      .orThrow();

    expect(account).toMatchObject({ scale: 0, allowNegative: true });
    expect(fake.calls).toEqual([
      [
        "open_ledger_account",
        {
          tenant: "org-1",
          kind: "points",
          code: "points:p1",
          name: "Points",
          unit: "points",
          scale: 2,
          holder_type: "party",
          holder_id: "p1",
          owner_id: "u1",
          allow_negative: true,
          read_permission: "parties.read",
          metadata: { tier: "gold" },
        },
      ],
      [
        "list_ledger_accounts",
        {
          tenant: "org-1",
          kind: "credit",
          holder_type: "party",
          holder_id: "p1",
          page_size: null,
        },
      ],
      [
        "post_ledger_transaction",
        {
          tenant: "org-1",
          kind: "credit.grant",
          lines: [
            { account: "a1", amount: "100" },
            { account: "a2", amount: "-100" },
          ],
          reference_type: "orders",
          reference_id: "o1",
          memo: "welcome",
          idempotency_key: "k1",
          effective_at: AT,
          metadata: { source: "signup" },
        },
      ],
      [
        "place_ledger_hold",
        {
          account_id: "a1",
          amount: "500",
          reference_type: "orders",
          reference_id: "o2",
          expires_at: AT,
        },
      ],
      [
        "capture_ledger_hold",
        {
          hold_id: "h1",
          to_account: "a2",
          amount: "200",
          kind: "gift_card.redeem",
          memo: "order o2",
        },
      ],
    ]);
  });

  it("sends null for every option it isn't given", async () => {
    const fake = fakeTransport({
      open_ledger_account: ACCOUNT,
      list_ledger_accounts: [],
      post_ledger_transaction: TRANSACTION,
      reverse_ledger_transaction: TRANSACTION,
      place_ledger_hold: HOLD,
      capture_ledger_hold: HOLD,
    });

    const ledger = createLedger({ transport: fake.transport, tenant: "org-1" });

    await ledger
      .openAccount({ kind: "cash", code: "cash", name: "Cash", unit: "EUR" })
      .orThrow();
    await ledger.accounts().orThrow();
    await ledger
      .post({
        kind: "cash.move",
        lines: [
          { accountId: "a1", amount: 1n },
          { accountId: "a2", amount: -1n },
        ],
      })
      .orThrow();
    await ledger.reverse("t1").orThrow();
    await ledger.hold("a1", { amount: 1n }).orThrow();
    await ledger.capture("h1", { toAccountId: "a2" }).orThrow();

    expect(fake.calls.map(([, args]) => args)).toEqual([
      {
        tenant: "org-1",
        kind: "cash",
        code: "cash",
        name: "Cash",
        unit: "EUR",
        scale: 0,
        holder_type: null,
        holder_id: null,
        owner_id: null,
        allow_negative: false,
        read_permission: null,
        metadata: null,
      },
      {
        tenant: "org-1",
        kind: null,
        holder_type: null,
        holder_id: null,
        page_size: null,
      },
      {
        tenant: "org-1",
        kind: "cash.move",
        lines: [
          { account: "a1", amount: "1" },
          { account: "a2", amount: "-1" },
        ],
        reference_type: null,
        reference_id: null,
        memo: null,
        idempotency_key: null,
        effective_at: undefined,
        metadata: null,
      },
      { transaction_id: "t1", memo: null },
      {
        account_id: "a1",
        amount: "1",
        reference_type: null,
        reference_id: null,
        expires_at: undefined,
      },
      {
        hold_id: "h1",
        to_account: "a2",
        amount: null,
        kind: "ledger.capture",
        memo: null,
      },
    ]);
  });

  it("loads a record's accounts for its section", async () => {
    const fake = fakeTransport({ list_ledger_accounts: [ACCOUNT] });
    const ledger = createLedger({ transport: fake.transport });

    const accounts = await ledgerBinding
      .load(ledger, { type: "party", id: "p1" }, undefined)
      .orThrow();

    expect(accounts.map((account) => account.id)).toEqual(["a1"]);
  });
});

describe("ledgerMoney", () => {
  it("returns Money for a currency and nothing for a custom unit", () => {
    expect(ledgerMoney({ unit: "EUR", balance: 1500n })).toEqual(
      money(1500n, "EUR"),
    );
    expect(ledgerMoney({ unit: "EUR", balance: 1500n }, 20n)).toEqual(
      money(20n, "EUR"),
    );
    expect(ledgerMoney({ unit: "points", balance: 10n })).toBeUndefined();
  });
});
