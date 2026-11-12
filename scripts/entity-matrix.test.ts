import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { BLOCK_MANIFESTS } from "../packages/better-supabase/src/blocks/registry.ts";
import {
  AUDIT_REPORT,
  entityMatrix,
  withEntityMatrix,
} from "./entity-matrix.ts";

describe("the entity matrix generated from the manifests", () => {
  it("keeps the audit report current", () => {
    const report = readFileSync(AUDIT_REPORT, "utf-8");

    expect(withEntityMatrix(report)).toBe(report);
  });

  it("has a row for every declared entity", () => {
    const matrix = entityMatrix();

    for (const block of BLOCK_MANIFESTS) {
      for (const key of Object.keys(block.entities)) {
        expect(matrix).toContain(`| ${block.name}`);
        expect(matrix).toContain(key);
      }
    }
  });

  it("returns undefined for a page without markers", () => {
    expect(withEntityMatrix("# No markers")).toBeUndefined();
  });
});
