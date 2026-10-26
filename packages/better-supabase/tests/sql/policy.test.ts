import { describe, expect, it } from "vitest";

import {
  maskSql,
  policy,
  readGrants,
  readPolicies,
  readPolicy,
  renderPolicy,
} from "../../src/sql/policy.ts";

describe("policy", () => {
  it("defaults to a permissive policy for all commands to public", () => {
    const built = policy({ table: "notes", name: "notes_all" });

    expect(built.command).toBe("all");
    expect(built.roles).toEqual(["public"]);
    expect(built.permissive).toBe(true);
    expect(built.table).toBe("public.notes");
  });

  it("renders and reads back the same policy", () => {
    const built = policy({
      table: "app.notes",
      name: "notes_read",
      command: "select",
      roles: ["authenticated"],
      using: "owner_id = auth.uid()",
    });

    const sql = renderPolicy(built, { drop: true });

    expect(sql.startsWith("drop policy if exists notes_read on")).toBe(true);
    expect(readPolicy(sql)).toEqual(built);
  });

  it("renders restrictive policies with a check clause", () => {
    const sql = renderPolicy(
      policy({
        table: "app.notes",
        name: "scope",
        permissive: false,
        roles: ["authenticated"],
        using: "true",
        check: "true",
      }),
    );

    expect(sql).toContain("as restrictive");
    expect(sql).toContain("with check (true)");
  });
});

describe("readPolicies", () => {
  it("ignores policies in comments and strings", () => {
    const sql = [
      "-- create policy a on t for select using (true);",
      "select 'create policy b on t for select using (true);';",
      "create policy c on t for select to public using (true);",
    ].join("\n");

    expect(readPolicies(sql).map((read) => read.policy.name)).toEqual(["c"]);
  });

  it("finds policies inside do blocks", () => {
    const sql = `do $$ begin
  create policy "in do" on "s"."t" for select to authenticated using (x = 'a)');
end $$;`;

    const [read] = readPolicies(sql);

    expect(read?.policy.name).toBe("in do");
    expect(read?.policy.using).toBe("x = 'a)'");
  });

  it("keeps quoted names apart when they mask alike", () => {
    const sql = [
      'create policy a on "s"."first" for select using (true);',
      'create policy b on "s"."second" for select using (true);',
    ].join("\n");

    expect(readPolicies(sql).map((read) => read.policy.table)).toEqual([
      "s.first",
      "s.second",
    ]);
  });

  it("skips a policy with unbalanced clauses", () => {
    expect(
      readPolicy("create policy a on t for select using (true;"),
    ).toBeUndefined();
  });
});

describe("readGrants", () => {
  it("reads table grants with quoted and qualified names", () => {
    const sql = [
      'grant select on "s"."a" to authenticated;',
      "grant insert, update on table s.b to anon, authenticated;",
      "-- grant all on s.c to anon;",
    ].join("\n");

    expect(readGrants(sql)).toEqual([
      { table: "s.a", roles: ["authenticated"] },
      { table: "s.b", roles: ["anon", "authenticated"] },
    ]);
  });
});

describe("maskSql", () => {
  it("blanks comments, strings and dollar bodies but keeps length", () => {
    const sql = "select 'a;b', $$x;y$$ -- z;\n;";

    const masked = maskSql(sql, { dollarBodies: "mask" });

    expect(masked).toHaveLength(sql.length);
    expect(masked).not.toContain("a;b");
    expect(masked).not.toContain("x;y");
  });
});
