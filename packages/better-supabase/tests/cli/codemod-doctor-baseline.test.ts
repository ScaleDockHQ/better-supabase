import { describe, expect, it } from "vitest";

import { groupedFromMap } from "../../src/cli/codemod-doctor-baseline.ts";
import { CODEMODS } from "../../src/cli/codemod.ts";

describe("codemod doctor-baseline", () => {
  it("is registered", () => {
    expect(CODEMODS["doctor-baseline"]?.name).toBe("doctor-baseline");
  });

  it("turns { code: { reason, targets } } into grouped entries", () => {
    expect(
      groupedFromMap({
        BS351: { reason: "migrating", targets: ["a.ts"] },
        BS200: { reason: "legacy", targets: ["public.notes"] },
      }),
    ).toEqual({
      groups: [
        { code: "BS351", reason: "migrating", targets: ["a.ts"] },
        { code: "BS200", reason: "legacy", targets: ["public.notes"] },
      ],
    });
  });

  it("names an entry without a reason", () => {
    expect(groupedFromMap({ BS351: { targets: [] } })).toEqual({
      problem: "has an entry for BS351 without a reason and targets",
    });
    expect(groupedFromMap("x")).toHaveProperty("problem");
  });
});
