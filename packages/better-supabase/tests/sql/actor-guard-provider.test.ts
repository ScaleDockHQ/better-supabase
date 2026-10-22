import { describe, expect, it } from "vitest";

import type { AuthorizationFunctions } from "../../src/config/authorization.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { applyActorWriteGuards } from "../../src/sql/actor-guard.ts";

const layoutWith = (template: string): BlockSqlLayout => {
  const functions: Partial<AuthorizationFunctions> = {
    actorMayWrite: template,
  };

  // SAFETY: the guard reads only accessProvider.functions.actorMayWrite.
  return { accessProvider: { functions } } as BlockSqlLayout;
};

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
