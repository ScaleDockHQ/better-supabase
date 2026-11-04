import { describe, expect, it } from "vitest";

import { blockSqlVersion } from "../../src/sql/module-types.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { upgradePlan } from "../../src/sql/upgrade.ts";

const withUpgrades = Object.entries(SQL_MODULES).filter(
  ([, module]) => (module.upgrades ?? []).length > 0,
);

const everything = Object.keys(SQL_MODULES).map((module) => ({
  module,
  version: 0,
}));

describe("module upgrade steps", () => {
  it("renders every step of every module next to all the others", () => {
    const plans = upgradePlan(everything, {});

    for (const [name, module] of withUpgrades) {
      const plan = plans.find((entry) => entry.module === name);

      expect([name, plan?.to]).toEqual([name, blockSqlVersion(module)]);
      expect([name, (plan?.steps.length ?? 0) > 0]).toEqual([name, true]);
    }
  });

  it.each(withUpgrades.map(([name]) => name))(
    "renders the steps of %s when it is the only module installed",
    (name) => {
      const [plan] = upgradePlan([{ module: name, version: 0 }], {});

      expect(plan?.steps.every((step) => typeof step.sql === "string")).toBe(
        true,
      );
    },
  );
});
