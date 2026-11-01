import { describe, expect, it } from "vitest";

import {
  createTills,
  tillInputSchema,
  tillsBlock,
} from "../../../src/blocks/tills/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const TILL = {
  id: "t1",
  organizationId: "org-1",
  name: "Front",
  currency: "EUR",
  accountId: "a1",
  createdAt: AT,
  updatedAt: AT,
};

const SESSION = {
  id: "s1",
  tillId: "t1",
  organizationId: "org-1",
  status: "open",
  currency: "EUR",
  openingFloat: "10000",
  expected: "10000",
  openedAt: AT,
};

const MOVEMENT = {
  id: "m1",
  sessionId: "s1",
  currency: "EUR",
  kind: "cash_sale",
  amount: "2500",
  createdAt: AT,
};

const COUNT = {
  id: "c1",
  sessionId: "s1",
  currency: "EUR",
  denominations: { "500": 25 },
  expected: "12500",
  counted: "12000",
  variance: "-500",
  countedAt: AT,
  entryId: "e1",
};

const DEPOSIT = {
  id: "d1",
  sessionId: "s1",
  currency: "EUR",
  amount: "12000",
  depositedOn: "2026-10-30",
  status: "pending",
  entryId: "e2",
  createdAt: AT,
};

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createTills", () => {
  it("creates, updates and lists tills", async () => {
    const t = fieldsTransport({
      create_till: () => TILL,
      update_till: () => ({ ...TILL, archivedAt: AT }),
      list_tills: () => [TILL],
    });

    const tills = createTills({ transport: t, tenant: "org-1" });

    const created = await tills
      .createTill({ name: "Front", currency: "EUR", accountId: "a1" })
      .orThrow();

    const archived = await tills
      .updateTill({ tillId: "t1", input: { archived: true } })
      .orThrow();

    const listed = await tills.listTills({ includeArchived: true }).orThrow();

    expect(created).toMatchObject({ name: "Front", accountId: "a1" });
    expect(archived.archivedAt?.toString()).toBe(
      temporal().Instant.from(AT).toString(),
    );
    expect(listed).toHaveLength(1);
    expect(t.calls).toEqual([
      [
        "create_till",
        {
          tenant: "org-1",
          input: { name: "Front", currency: "EUR", accountId: "a1" },
        },
      ],
      ["update_till", { till_id: "t1", input: { archived: true } }],
      ["list_tills", { tenant: "org-1", filters: { archived: true } }],
    ]);
  });

  it("opens a session with a float and records movements", async () => {
    const t = fieldsTransport({
      open_till_session: () => SESSION,
      record_till_movement: () => MOVEMENT,
    });

    const tills = createTills({ transport: t, tenant: "org-1" });

    const session = await tills
      .openSession({ tillId: "t1", openingFloat: money(10_000n, "EUR") })
      .orThrow();

    const movement = await tills
      .recordMovement({
        sessionId: "s1",
        kind: "cash_sale",
        amount: money(2500n, "EUR"),
        reference: "ORD-1",
      })
      .orThrow();

    expect(session.openingFloat).toEqual(money(10_000n, "EUR"));
    expect(session.status).toBe("open");
    expect(movement).toMatchObject({
      kind: "cash_sale",
      amount: money(2500n, "EUR"),
    });
    expect(t.calls).toEqual([
      ["open_till_session", { till_id: "t1", opening_float: "10000" }],
      [
        "record_till_movement",
        {
          session_id: "s1",
          kind: "cash_sale",
          amount: "2500",
          reference: "ORD-1",
        },
      ],
    ]);
  });

  it("closes a session with denominations and reads the count", async () => {
    const t = fieldsTransport({
      close_till_session: () => ({
        ...SESSION,
        status: "closed",
        closedAt: AT,
        movements: [MOVEMENT],
        count: COUNT,
        deposits: [],
      }),
    });

    const tills = createTills({ transport: t, tenant: "org-1" });

    const closed = await tills
      .closeSession({
        sessionId: "s1",
        input: { denominations: { "500": 25 } },
      })
      .orThrow();

    expect(closed.status).toBe("closed");
    expect(closed.count).toMatchObject({
      variance: money(-500n, "EUR"),
      denominations: { "500": 25 },
      entryId: "e1",
    });
    expect(t.calls[0]).toEqual([
      "close_till_session",
      { session_id: "s1", input: { denominations: { "500": 25 } } },
    ]);
  });

  it("reads a session with its deposits", async () => {
    const t = fieldsTransport({
      get_till_session: () => ({
        ...SESSION,
        status: "closed",
        movements: [MOVEMENT],
        count: COUNT,
        deposits: [DEPOSIT],
      }),
      list_till_sessions: () => [SESSION],
    });

    const tills = createTills({ transport: t, tenant: "org-1" });
    const detail = await tills.getSession("s1").orThrow();
    const sessions = await tills.listSessions({ tillId: "t1" }).orThrow();

    expect(detail.movements).toHaveLength(1);
    expect(detail.deposits[0]?.depositedOn.toString()).toBe("2026-10-30");
    expect(sessions).toHaveLength(1);
    expect(t.calls[1]).toEqual([
      "list_till_sessions",
      { tenant: "org-1", filters: { tillId: "t1" } },
    ]);
  });

  it("deposits cash and reconciles the deposit", async () => {
    const t = fieldsTransport({
      deposit_till_cash: () => DEPOSIT,
      reconcile_till_deposit: () => ({
        ...DEPOSIT,
        status: "reconciled",
        bankTransactionId: "b1",
        reconciledAt: AT,
      }),
    });

    const tills = createTills({ transport: t, tenant: "org-1" });

    const deposit = await tills
      .deposit({
        sessionId: "s1",
        input: {
          amount: money(12_000n, "EUR"),
          depositedOn: temporal().PlainDate.from("2026-10-30"),
        },
      })
      .orThrow();

    const reconciled = await tills
      .reconcileDeposit({ depositId: "d1", bankTransactionId: "b1" })
      .orThrow();

    expect(deposit.status).toBe("pending");
    expect(reconciled).toMatchObject({
      status: "reconciled",
      bankTransactionId: "b1",
    });
    expect(t.calls).toEqual([
      [
        "deposit_till_cash",
        {
          session_id: "s1",
          input: { amount: "12000", depositedOn: "2026-10-30" },
        },
      ],
      [
        "reconcile_till_deposit",
        { deposit_id: "d1", bank_transaction_id: "b1" },
      ],
    ]);
  });

  it("rejects a malformed row", async () => {
    const t = fieldsTransport({
      open_till_session: () => ({ ...SESSION, status: "paused" }),
    });

    const tills = createTills({ transport: t, tenant: "org-1" });
    const result = await tills.openSession({ tillId: "t1" });

    expect(result.ok).toBe(false);
  });

  it("validates the till input and names the block", () => {
    expect(
      validate(tillInputSchema, { name: "Front", currency: "EUR" }).issues,
    ).toBeUndefined();
    expect(
      validate(tillInputSchema, { name: "", currency: "EUR" }).issues,
    ).toBeDefined();
    expect(tillsBlock.name).toBe("tills");
  });
});
