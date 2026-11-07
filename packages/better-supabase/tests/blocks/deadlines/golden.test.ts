import { describe, expect, it } from "vitest";

import {
  evaluateVersion,
  validateRuleVersion,
} from "../../../src/blocks/deadlines/index.ts";
import { contentOf, GOLDEN } from "../../fixtures/deadlines.ts";

const REFUSALS = new Set(["barred", "not_applicable", "not_required"]);

const CASES = GOLDEN.flatMap((fixture) =>
  fixture.cases.map((test) => ({
    label: `${fixture.name}: ${test.name}`,
    fixture,
    test,
  })),
);

describe("golden deadline fixtures in TypeScript", () => {
  it("finds the fixtures", () => {
    expect(GOLDEN.map((fixture) => fixture.name)).toEqual([
      "ak-ca-co",
      "az",
      "calendar",
      "mn-ks",
      "tx",
      "v1",
    ]);
  });

  it.each(GOLDEN.map((fixture) => [fixture.name, fixture] as const))(
    "%s is a valid version",
    (_name, fixture) => {
      expect(validateRuleVersion(fixture.content)).toEqual([]);
    },
  );

  it.each(CASES.map((entry) => [entry.label, entry] as const))(
    "%s",
    (_label, { fixture, test }) => {
      const results = evaluateVersion(
        contentOf(fixture, test),
        test.facts,
        test.asOf,
        test.group,
      );

      expect(JSON.parse(JSON.stringify(results))).toEqual(test.expect);
      expect(
        results.filter(
          (result) =>
            (result.result === "due") !== (result.dueOn !== null) ||
            (result.period !== null && result.result !== "due") ||
            result.missing.length > 0 !==
              (result.result === "unknown" || result.provisional) ||
            (result.exception !== null && !REFUSALS.has(result.result)),
        ),
      ).toEqual([]);
    },
  );
});
