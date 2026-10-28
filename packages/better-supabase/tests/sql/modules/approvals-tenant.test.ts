import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

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

    expect(sql).toContain("create table if not exists");
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
});
