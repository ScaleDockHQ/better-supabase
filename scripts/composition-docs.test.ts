import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { PRESET_CATALOG } from "../packages/better-supabase/src/preset/catalog.generated.ts";
import {
  AUTOMATIONS_PAGE,
  defaultAutomations,
  MATRIX_PAGE,
  moduleMatrix,
} from "./composition-docs.ts";

describe("the docs tables generated from the catalog", () => {
  it("keeps the module matrix current", () => {
    expect(readFileSync(MATRIX_PAGE, "utf-8")).toContain(moduleMatrix());
  });

  it("keeps the default automations table current", () => {
    expect(readFileSync(AUTOMATIONS_PAGE, "utf-8")).toContain(
      defaultAutomations(PRESET_CATALOG),
    );
  });

  it("lists every shipped automation", () => {
    const table = defaultAutomations(PRESET_CATALOG);

    for (const manifest of PRESET_CATALOG.manifests) {
      for (const automation of manifest.automations ?? []) {
        expect(table).toContain(`\`${automation.trigger}\``);
      }
    }
  });
});
