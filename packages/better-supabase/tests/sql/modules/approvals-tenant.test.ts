import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (modules: readonly string[], layout: Layout = {}): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "approvals")
    .map((file) => file.contents)
    .join("\n");

const approvals = (options: Record<string, unknown>): Layout => ({
  modules: { approvals: { options } },
});

const FLOORS = {
  invoice: {
    send: { steps: [{ approvers: { role: "admin" } }] },
    refund: { steps: [] },
    export: { mode: "confirm", steps: [] },
  },
};

describe("approval policies", () => {
  it("merges enabled tenant policies over the config floor", () => {
    const sql = sqlOf(
      ["automations", "approvals"],
      approvals({ policies: FLOORS, tenantPolicies: true }),
    );

    expect(sql).toContain("create table");
    expect(sql).toContain("approval_policies");
    expect(sql).toContain(`rule_matches"(`);
    expect(sql).toContain("save_approval_policy");
    expect(sql).toContain("remove_approval_policy");
    expect(sql).toContain("list_approval_policies");
    expect(sql).not.toContain("APPROVAL_CONDITIONS_UNSUPPORTED");
    expect(sql).toContain(`"run":null,"mode":"confirm"}'`);
    expect(sql).toContain("APPROVAL_NOT_REQUIRED");
    expect(sql).toContain("consume_approval");
  });

  it("checks a tenant step's required count against its users", () => {
    const sql = sqlOf(
      ["approvals"],
      approvals({ policies: FLOORS, tenantPolicies: true }),
    );

    expect(sql).toContain(
      "and (v_step ->> 'required')::numeric > jsonb_array_length(v_step -> 'approvers' -> 'users'))",
    );
    expect(sql).toContain(
      "then jsonb_set(s, '{required}', to_jsonb(jsonb_array_length(s -> 'approvers' -> 'users')))",
    );
  });

  it("skips conditions without automations and renders plain SQL when off", () => {
    const on = sqlOf(
      ["approvals"],
      approvals({ policies: FLOORS, tenantPolicies: true }),
    );

    expect(on).toContain("save_approval_policy");
    expect(on).not.toContain(`rule_matches"(`);
    expect(on).toContain("APPROVAL_CONDITIONS_UNSUPPORTED");

    const off = sqlOf(
      ["approvals"],
      approvals({ policies: { invoice: { send: FLOORS.invoice.send } } }),
    );

    expect(off).not.toContain("save_approval_policy");
    expect(off).toContain("approval_requirement");
    expect(off).toContain("consume_approval");
  });

  it("resolves a manager approver through employees", () => {
    const sql = sqlOf(
      ["employees", "approvals"],
      approvals({
        policies: {
          invoice: { send: { steps: [{ approvers: { manager: true } }] } },
        },
      }),
    );

    expect(sql).toContain("v_approvers ->> 'manager'");
    expect(sql).toContain("offboarded");
  });

  it("refuses a manager approver without employees", () => {
    expect(() =>
      sqlOf(
        ["approvals"],
        approvals({
          policies: {
            invoice: { send: { steps: [{ approvers: { manager: true } }] } },
          },
        }),
      ),
    ).toThrow(/employees/);
  });

  it("refuses an empty authorize floor without tenant policies", () => {
    expect(() =>
      sqlOf(
        ["approvals"],
        approvals({ policies: { invoice: { refund: { steps: [] } } } }),
      ),
    ).toThrow(/tenantPolicies/);
  });

  it("refuses a bad mode and a manager that is not true", () => {
    expect(() =>
      sqlOf(
        ["approvals"],
        approvals({
          policies: {
            invoice: {
              send: { mode: "later", steps: [{ approvers: { role: "a" } }] },
            },
          },
        }),
      ),
    ).toThrow(/mode/);
    expect(() =>
      sqlOf(
        ["employees", "approvals"],
        approvals({
          policies: {
            invoice: { send: { steps: [{ approvers: { manager: "yes" } }] } },
          },
        }),
      ),
    ).toThrow(/manager/);
  });

  it("moves a consumed request to consumed and ties consumed_at to it", () => {
    const sql = sqlOf(
      ["approvals"],
      approvals({ policies: { invoice: { send: FLOORS.invoice.send } } }),
    );

    expect(sql).toContain(`set "status" = 'consumed', "consumed_at" = now()`);
    expect(sql).toContain(
      `check (("status" = 'consumed') = ("consumed_at" is not null))`,
    );
    expect(sql).toContain(`x."status"::text in ('approved', 'consumed')`);
  });

  it("backfills requests used before the consumed status on upgrade", () => {
    const [plan] = upgradePlan(
      [{ module: "approvals", version: 5 }],
      approvals({ policies: FLOORS }),
    );

    const sql = plan?.steps.map((step) => step.sql).join("\n") ?? "";

    expect(plan?.to).toBe(6);
    expect(sql).toContain(
      `drop constraint if exists "approval_requests_status_check"`,
    );
    expect(sql).toContain(
      `set "status" = 'consumed' where "consumed_at" is not null and "status" = 'approved'`,
    );
    expect(sql).toContain(`"bsb_approval_requests_consumed_check"`);
  });

  it("leaves an app's own requests table to the app on upgrade", () => {
    const [plan] = upgradePlan([{ module: "approvals", version: 5 }], {
      ownTables: { "public.approval_requests": "app.sql" },
      modules: {
        approvals: {
          tables: { requests: "public.approval_requests" },
          options: { policies: FLOORS },
        },
      },
    });

    expect(plan?.steps.map((step) => step.sql).join("")).toBe("");
  });

  it("keeps the status of an app's own requests table when it consumes", () => {
    const sql = sqlOf(["approvals"], {
      ownTables: { "public.approval_requests": "app.sql" },
      modules: {
        approvals: {
          tables: { requests: "public.approval_requests" },
          options: { policies: { invoice: { send: FLOORS.invoice.send } } },
        },
      },
    });

    expect(sql).toContain(`r set "consumed_at" = now()`);
    expect(sql).not.toContain(`set "status" = 'consumed'`);
  });
});
