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

  it("replaces calls but keeps the built-in's own declaration and grants", () => {
    const sql = [
      "create or replace function better_supabase.actor_may_write()",
      "returns boolean language sql as $$ select true $$;",
      "revoke execute on function better_supabase.actor_may_write() from public;",
      "grant execute on function better_supabase.actor_may_write() to authenticated;",
      "create policy p on t for insert with check ((select better_supabase.actor_may_write()));",
    ].join("\n");

    const guarded = applyActorWriteGuards(sql, layoutWith("app.may_write()"));

    expect(guarded).toContain(
      "create or replace function better_supabase.actor_may_write()",
    );
    expect(guarded).toContain(
      "revoke execute on function better_supabase.actor_may_write() from public;",
    );
    expect(guarded).toContain(
      "grant execute on function better_supabase.actor_may_write() to authenticated;",
    );
    expect(guarded).toContain("with check ((select (app.may_write())));");
    expect(guarded).not.toContain("function (app.may_write())");
  });
});
