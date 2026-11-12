import { describe, expect, it } from "vitest";

import {
  customerRows,
  inImportMode,
  parseArgs,
  planSeed,
  renderStep,
  SEED_RUN,
  tierSpec,
} from "./seed-scale-plan.ts";

describe("seed-scale-plan", () => {
  it("counts the customers of a tier", () => {
    expect(customerRows(tierSpec("m"))).toBe(60_000);
    expect(customerRows(tierSpec("l"))).toBe(1_000_000 + 999 * 100);
    expect(customerRows(tierSpec("l", 11))).toBe(1_000_000 + 10 * 100);
  });

  it("splits each area into batches that cover it once", () => {
    const steps = planSeed("l");

    for (const area of ["customers", "notes"] as const) {
      const own = steps.filter((step) => step.area === area);

      const gaps = own.flatMap((step, index) => {
        const next = own[index + 1];

        return next && next.from !== step.to + 1 ? [index] : [];
      });

      expect(own[0]?.from).toBe(1);
      expect(own.at(-1)?.to).toBe(customerRows(tierSpec("l")));
      expect(gaps).toEqual([]);
    }
  });

  it("gives the append-only areas their own volume", () => {
    const xl = planSeed("xl");
    const audit = xl.filter((step) => step.area === "audit");

    expect(audit.at(-1)?.to).toBe(10_000_000);
    expect(audit[0]?.vars["total"]).toBe(10_000_000);
    expect(planSeed("m").some((step) => step.area === "audit")).toBe(false);
  });

  it("writes the other tenants before the rows that belong to them", () => {
    expect(planSeed("smoke").map((step) => step.area)).toEqual([
      "tenants",
      "customers",
      "notes",
      "audit",
      "notifications",
    ]);
  });

  it("fills every placeholder of a generator", () => {
    const step = planSeed("smoke").find((s) => s.area === "customers");

    if (!step) {
      throw new Error("no customers step");
    }

    const sql = renderStep(
      "select {{from}}, {{to}}, {{hot}}, {{tenants}}",
      step,
    );

    expect(sql).toBe("select 1, 600, 300, 3");
  });

  it("refuses a placeholder no step sets", () => {
    const [step] = planSeed("smoke");

    if (!step) {
      throw new Error("no step");
    }

    expect(() => renderStep("select {{missing}}", step)).toThrow(
      "no step sets",
    );
  });

  it("wraps a batch in a transaction in import mode", () => {
    expect(inImportMode("insert into t values (1);\n")).toBe(
      `begin;\nselect better_supabase.begin_import_session('${SEED_RUN}');\ninsert into t values (1);\ncommit;\n`,
    );
  });

  it("parses the flags and refuses a bad one", () => {
    expect(parseArgs(["--tier", "l", "--tenants", "50", "--dry-run"])).toEqual({
      tier: "l",
      tenants: 50,
      dryRun: true,
      clean: false,
      notificationsOnly: false,
    });

    expect(parseArgs(["notifications"]).notificationsOnly).toBe(true);
    expect(parseArgs(["--tier", "m", "--clean"]).clean).toBe(true);
    expect(() => parseArgs(["--tier", "huge"])).toThrow("--tier takes");
    expect(() => parseArgs(["--tenants", "1"])).toThrow("at least 2");
  });
});
