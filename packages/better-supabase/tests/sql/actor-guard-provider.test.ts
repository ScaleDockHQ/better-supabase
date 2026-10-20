import { describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { applyActorWriteGuards } from "../../src/sql/actor-guard.ts";

const layoutWith = (template: string): ModuleLayout =>
  // SAFETY: the guard reads only accessProvider.functions.actorMayWrite.
  ({
    accessProvider: { functions: { actorMayWrite: template } },
  });

describe("applyActorWriteGuards with a provider template", () => {
  it("refuses a template with placeholders", () => {
    expect(() =>
      applyActorWriteGuards("select 1;", layoutWith("app.may({tenant})")),
    ).toThrow("takes no placeholders");
  });

  it("accepts a template without placeholders", () => {
    expect(() =>
      applyActorWriteGuards("select 1;", layoutWith("app.may_write()")),
    ).not.toThrow();
  });
});
