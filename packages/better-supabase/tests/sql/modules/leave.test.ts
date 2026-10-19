import { describe, expect, it } from "vitest";

import { customContracts, renderModules } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderModules>[1];

const sqlOf = (
  modules: readonly string[],
  layout: Layout = {},
  module = "leave",
): string =>
  renderModules(modules, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const BASE = ["approvals", "leave"];

const options = (value: Record<string, unknown>): Layout => ({
  modules: { leave: { options: value } },
});

describe("leave module", () => {
  it("counts working days from options.workingDays", () => {
    expect(sqlOf(BASE)).toContain(
      "extract(isodow from d)::integer = any (array[1, 2, 3, 4, 5])",
    );
    expect(
      sqlOf(BASE, options({ workingDays: ["sun", "mon", "mon"] })),
    ).toContain("= any (array[1, 7])");
    expect(() => sqlOf(BASE, options({ workingDays: [] }))).toThrow(
      /at least one day/,
    );
    expect(() =>
      sqlOf(BASE, options({ workingDays: ["fri", "funday"] })),
    ).toThrow(/"funday" is not one of/);
  });

  it("keeps a signed ledger per member, type and year", () => {
    const sql = sqlOf(BASE);
    expect(sql).toContain(
      `check ("kind" in ('grant', 'accrual', 'taken', 'adjustment', 'carryover', 'expiry'))`,
    );
    expect(sql).toContain(
      `"amount" numeric(8, 2) not null check ("amount" <> 0)`,
    );
    expect(sql).toContain(
      `create unique index if not exists "leave_ledger_key_idx" on "better_supabase"."leave_ledger" ("tenant_id", "user_id", "type_id", "idempotency_key") where "idempotency_key" is not null;`,
    );
  });

  it("checks the balance unless allowNegative is on", () => {
    expect(sqlOf(BASE)).toContain("LEAVE_BALANCE_EXCEEDED");
    expect(sqlOf(BASE, options({ allowNegative: true }))).not.toContain(
      "LEAVE_BALANCE_EXCEEDED",
    );
  });

  it("files requests under options.policy without a run", () => {
    expect(sqlOf(BASE)).toContain(`"permission":"leave.approve"`);
    expect(
      sqlOf(
        BASE,
        options({ policy: { steps: [{ approvers: { role: "admin" } }] } }),
      ),
    ).toContain(`"role":"admin"`);
    expect(() =>
      sqlOf(
        BASE,
        options({
          policy: {
            steps: [{ approvers: { role: "admin" } }],
            run: { kind: "queue", queue: "x" },
          },
        }),
      ),
    ).toThrow(/policy\.run is not allowed/);
  });

  it("lets approvals book the leave on the final approval", () => {
    const approvals = sqlOf(BASE, {}, "approvals");
    expect(approvals).toContain(`"better_supabase"."approve_leave_request"(`);
    expect(approvals).toContain("'leave_request'");
    expect(sqlOf(["approvals"], {}, "approvals")).not.toContain(
      "approve_leave_request",
    );
  });

  it("carries a year's balance up to carryoverMax and expires the rest", () => {
    const sql = sqlOf(BASE);
    expect(sql).toContain(
      `('carryover', b.carry, close_leave_year.period + 1)`,
    );
    expect(sql).toContain(
      `('expiry', -(b.balance - b.carry), close_leave_year.period)`,
    );
    expect(sql).toContain(
      "do nothing;\n  get diagnostics v_written = row_count;",
    );
  });

  it("needs the approvals tables", () => {
    expect(() =>
      sqlOf(BASE, { modules: { approvals: { mode: "custom" } } }),
    ).toThrow(/approvals can't be in custom mode/);
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { leave: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    const [contract] = customContracts(["leave"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual([
      "request_leave",
      "cancel_leave_request",
      "leave_balances",
      "list_leave_requests",
    ]);
  });
});
