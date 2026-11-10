import { describe, expect, it } from "vitest";

import { DEADLINES } from "../../../src/sql/modules/deadlines.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "deadlines"];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "deadlines")
    .map((file) => file.contents)
    .join("\n");

describe("deadlines module", () => {
  it("renders the rule set, version and deadline tables and the frozen trigger", () => {
    const sql = sqlOf();

    expect(sql).toContain('"deadline_rule_sets"');
    expect(sql).toContain('"deadline_rule_versions"');
    expect(sql).toContain("DEADLINE_RULE_VERSION_FROZEN");
    expect(sql).toContain("'draft', 'approved'");
    expect(sql).toContain(
      "'due', 'unknown', 'pending', 'undated', 'not_covered', 'not_applicable', 'not_required', 'barred'",
    );
    expect(sql).toContain('"bsb_deadlines_subject_group_period_key"');
    expect(sql).not.toContain('"deadlines_subject_rule_key"');
  });

  it("keeps the version 1 functions as deprecated wrappers", () => {
    const sql = sqlOf();

    expect(sql).toContain("Deprecated since 0.56.0");
    expect(sql).toContain("'deprecated: use evaluate_deadlines'");
    expect(sql).toContain("'deprecated: use compute_deadlines'");
  });

  it("upgrades version 1 in one step that converts the rules and drops the renamed functions", () => {
    const [plan] = upgradePlan([{ module: "deadlines", version: 1 }]);

    expect(plan?.to).toBe(2);
    expect(plan?.steps.map((step) => step.from)).toEqual([1]);
    expect(plan?.steps[0]?.sql).toContain(
      "disable trigger bsb_deadlines_version_frozen",
    );
    expect(plan?.steps[0]?.sql).toContain("previous_content_hash");
    expect(plan?.steps[0]?.sql).toContain(
      'drop function if exists "better_supabase"."save_rule_version"(text, text, jsonb, date, text)',
    );
    expect(
      upgradePlan([{ module: "deadlines", version: 1 }], {
        modules: { deadlines: { mode: "custom" } },
      })[0]?.steps[0]?.sql ?? "",
    ).toBe("");
  });

  it("keeps the rule sets platform-wide and readable only when approved", () => {
    const sql = sqlOf();

    expect(sql).toMatch(/for select to authenticated\s+using \(true\)/);
    expect(sql).toContain(`"status" = 'approved'`);
  });

  it("asks for an approved request only when approvals is installed", () => {
    expect(sqlOf()).not.toContain("DEADLINE_APPROVAL_REQUIRED");
    expect(sqlOf([...BASE, "approvals"])).toContain(
      "DEADLINE_APPROVAL_REQUIRED",
    );
  });

  it("lets every subject through without subjects", () => {
    const sql = sqlOf();

    expect(sql).toContain(
      `using ("tenant_id" in (select better_supabase.tenant_ids_with('deadlines.read')) and true)`,
    );
    expect(sql).toMatch(
      /"deadline_subject_readable"\(subject_type text, subject_id text, tenant uuid\)[\s\S]*?security invoker[\s\S]*?return true;/u,
    );
  });

  it("checks the subject on every read and on compute, recompute and satisfy", () => {
    const sql = sqlOf(BASE, {
      modules: {
        deadlines: {
          on: {
            job: {
              table: "public.jobs",
              idType: "uuid",
              permission: "jobs.read",
            },
          },
        },
      },
    });

    expect(sql).toContain(
      `when 'job' then exists (select 1 from "public"."jobs" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."organization_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'jobs.read'), false)`,
    );
    expect(sql).toContain("else false");
    expect(sql).toMatch(
      /"list_deadlines"\(tenant uuid, filters jsonb default '\{\}'\)\nreturns jsonb\nlanguage plpgsql\nstable\nsecurity invoker/u,
    );

    for (const call of [
      `"deadline_subject_readable"(compute_deadlines.subject_type, compute_deadlines.subject_id, compute_deadlines.tenant)`,
      `"deadline_subject_readable"(recompute_deadlines.subject_type, recompute_deadlines.subject_id, recompute_deadlines.tenant)`,
      `"deadline_subject_readable"(v_row."subject_type", v_row."subject_id", v_row."tenant_id")`,
    ]) {
      expect(sql).toContain(call);
    }
  });

  it("clears the pending rows of groups a new version dropped on compute", () => {
    const sql = sqlOf();

    expect(sql).toContain(
      `and x."subject_id" = compute_deadlines.subject_id and x."jurisdiction" = compute_deadlines.jurisdiction
          and x."kind" = compute_deadlines.kind)`,
    );
    expect(sql).toMatch(
      /delete from "better_supabase"\."deadlines" x[\s\S]*?x\."state" = 'pending'[\s\S]*?x\."group_key" = any \(p_group_keys\)/u,
    );
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { deadlines: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    const [contract] = customContracts(["deadlines"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining(["compute_deadlines", "approve_rule_version"]),
    );
    expect(DEADLINES.name).toBe("deadlines");
  });
});
