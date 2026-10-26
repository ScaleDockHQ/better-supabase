import { describe, expect, it } from "vitest";

import type { PlanLike } from "../../src/create/plan-gate.ts";

import { gatePlan, parseRenameHints } from "../../src/create/plan-gate.ts";

const plan: PlanLike = {
  actions: [
    {
      sql: "alter table public.a add column x int",
      verb: "alter",
      dataLoss: "none",
    },
    { sql: "drop table public.old", verb: "drop", dataLoss: "destructive" },
  ],
  renameCandidates: [
    {
      kind: "table",
      from: "table:public.old",
      to: "table:public.new",
      status: "unambiguous",
    },
    {
      kind: "table",
      from: "table:public.p",
      to: "table:public.q",
      status: "unambiguous",
    },
    {
      kind: "table",
      from: "table:public.m",
      to: "table:public.n",
      status: "ambiguous",
    },
  ],
};

describe("parseRenameHints", () => {
  it("reads rename lines", () => {
    expect(
      parseRenameHints(
        "-- bsb: rename old -> new\nselect 1;\n-- bsb: rename public.p->q",
      ),
    ).toEqual([
      { from: "old", to: "new" },
      { from: "public.p", to: "q" },
    ]);
  });
});

describe("gatePlan", () => {
  it("blocks data loss and asks about unconfirmed renames", () => {
    const gate = gatePlan(plan);

    expect(gate.blocked).toBe(true);
    expect(gate.accepted).toEqual([]);
    expect(gate.questions).toHaveLength(2);
    expect(gate.unresolved).toHaveLength(1);
    expect(gate.issues.map((issue) => issue.code)).toEqual([
      "plan_rename_question",
      "plan_rename_question",
      "plan_rename_unresolved",
      "plan_data_loss",
    ]);
  });

  it("accepts a recorded rename and lets data loss through when allowed", () => {
    const gate = gatePlan(plan, {
      allowDataLoss: true,
      hints: [{ from: "old", to: "new" }],
    });

    expect(gate.accepted).toHaveLength(1);
    expect(gate.questions).toHaveLength(1);
    expect(gate.blocked).toBe(false);
    expect(
      gate.issues.find((issue) => issue.code === "plan_data_loss")?.severity,
    ).toBe("warning");
  });

  it("never accepts an ambiguous candidate", () => {
    const gate = gatePlan(plan, { hints: [{ from: "m", to: "n" }] });

    expect(gate.accepted).toEqual([]);
  });
});
