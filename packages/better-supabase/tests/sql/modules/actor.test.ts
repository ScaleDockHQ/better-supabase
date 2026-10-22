import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sql = renderBlocks(["actor"], {})
  .filter((file) => file.module === "actor")
  .map((file) => file.contents)
  .join("\n");

describe("actor module", () => {
  it("defines token_scope_allows for delegated client tokens", () => {
    expect(sql).toContain(
      "create or replace function better_supabase.token_scope_allows(p_scope text)",
    );
    expect(sql).toMatch(/token_scope_allows[\s\S]*security invoker/);
    expect(sql).toContain("jwt ->> 'client_id'");
    expect(sql).toContain("in ('support', 'impersonation')");
    expect(sql).toContain("@> jsonb_build_array(p_scope)");
    expect(sql).toContain(
      "grant execute on function better_supabase.token_scope_allows(text) to anon, authenticated, service_role;",
    );
  });

  it("keeps actor_may_write next to it", () => {
    expect(sql).toContain("function better_supabase.actor_may_write()");
  });
});
