import { describe, expect, it } from "vitest";

import type { Rule } from "../../src/sql/policy-rule.ts";

import {
  disallowedPolicyCalls,
  isRule,
  policyFunctionsSql,
  readRulePolicies,
  renderRule,
  renderRulePolicy,
  rulePolicy,
} from "../../src/sql/policy-rule.ts";
import { policy } from "../../src/sql/policy.ts";

const rule: Rule = {
  kind: "or",
  rules: [
    { kind: "owner", column: "owner_id" },
    {
      kind: "and",
      rules: [
        { kind: "member", column: "tenant_id" },
        { kind: "compare", column: "status", op: "=", value: "it's open" },
        { kind: "null", column: "deleted_at", isNull: true },
      ],
    },
    {
      kind: "not",
      rule: { kind: "can", column: "tenant_id", permission: "x" },
    },
  ],
};

describe("renderRule", () => {
  it("renders every kind with the bsb functions", () => {
    expect(renderRule(rule)).toBe(
      `(bsb.owns("owner_id")) or ((bsb.is_member("tenant_id")) and ("status" = 'it''s open') and ("deleted_at" is null)) or (not (bsb.can("tenant_id", 'x')))`,
    );
  });

  it("rejects columns that are not plain identifiers", () => {
    expect(() => renderRule({ kind: "owner", column: 'a"; drop' })).toThrow(
      "plain identifier",
    );
  });

  it("renders empty groups as constants", () => {
    expect(renderRule({ kind: "and", rules: [] })).toBe("true");
    expect(renderRule({ kind: "or", rules: [] })).toBe("false");
  });
});

describe("isRule", () => {
  it("accepts rule trees and refuses anything else", () => {
    expect(isRule(rule)).toBe(true);
    expect(isRule({ kind: "compare", column: "a", op: "like", value: 1 })).toBe(
      false,
    );
    expect(isRule({ kind: "and", rules: [{ kind: "nope" }] })).toBe(false);
    expect(isRule(null)).toBe(false);
  });
});

describe("rule policies", () => {
  const built = rulePolicy({
    table: "app.notes",
    name: "notes_read",
    command: "select",
    roles: ["authenticated"],
    using: rule,
  });

  it("reads the rules back from the comment", () => {
    const sql = `create table app.notes (id int);\n${renderRulePolicy(built, { drop: true })}\n`;
    const [read] = readRulePolicies(sql);

    expect(read?.using).toEqual(rule);
    expect(read?.inSync).toBe(true);
    expect(read?.policy).toEqual(built.policy);
  });

  it("flags a policy edited by hand", () => {
    const sql = renderRulePolicy(built).replace("bsb.owns", "bsb.uid() =");
    const [read] = readRulePolicies(sql);

    expect(read?.inSync).toBe(false);
  });

  it("ignores policies without a rule comment or with a bad one", () => {
    const plain = "create policy a on app.t for select using (true);";

    expect(readRulePolicies(plain)).toEqual([]);
    expect(readRulePolicies(`-- @bsb rule {oops\n${plain}`)).toEqual([]);
  });
});

describe("disallowedPolicyCalls", () => {
  it("allows only the bsb functions", () => {
    expect(
      disallowedPolicyCalls(
        rulePolicy({ table: "t", name: "n", using: rule }).policy,
      ),
    ).toEqual([]);

    const raw = policy({
      table: "t",
      name: "n",
      using:
        "auth.uid() = owner_id and exists (select 1 from x where public.f(x.id)) and bsb.owns(a)",
      check: "lower(name) = 'a(b)'",
    });

    expect(disallowedPolicyCalls(raw)).toEqual([
      "auth.uid",
      "lower",
      "public.f",
    ]);
  });
});

describe("policyFunctionsSql", () => {
  it("defines the four functions and takes overrides", () => {
    const sql = policyFunctionsSql({
      memberships: "app.my_tenants()",
      permission: "app.can",
      scope: "team",
    });

    for (const name of ["uid", "owns", "is_member", "can"]) {
      expect(sql).toContain(`function bsb.${name}(`);
    }

    expect(sql).toContain("app.my_tenants()");
    expect(sql).toContain("app.can('team', tenant, permission_key)");
  });
});

describe("rule edge cases", () => {
  it("renders public, numbers and booleans, and refuses bad values", () => {
    expect(renderRule({ kind: "public" })).toBe("true");
    expect(
      renderRule({ kind: "compare", column: "n", op: ">=", value: 3 }),
    ).toBe(`"n" >= 3`);
    expect(
      renderRule({ kind: "compare", column: "b", op: "<>", value: false }),
    ).toBe(`"b" <> false`);
    expect(() =>
      renderRule({ kind: "compare", column: "n", op: "=", value: Number.NaN }),
    ).toThrow("finite");
    expect(() =>
      renderRule({ kind: "compare", column: "n", op: "like" as ">", value: 1 }),
    ).toThrow("operator");
    expect(isRule({ kind: "public" })).toBe(true);
  });

  it("skips rule comments that are not objects or hold bad rules", () => {
    const plain = "create policy a on app.t for select using (true);";

    expect(readRulePolicies(`-- @bsb rule [1]\n${plain}`)).toEqual([]);
    expect(
      readRulePolicies(`-- @bsb rule {"using":{"kind":"x"}}\n${plain}`),
    ).toEqual([]);
  });

  it("reads rule policies that have only a check clause", () => {
    const built = rulePolicy({
      table: "app.t",
      name: "c",
      command: "insert",
      check: { kind: "public" },
    });

    const [read] = readRulePolicies(renderRulePolicy(built));

    expect(read?.check).toEqual({ kind: "public" });
    expect(read?.using).toBeNull();
  });
});
