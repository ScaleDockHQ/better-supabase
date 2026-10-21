import { describe, expect, it } from "vitest";

import { computedWrites } from "../../src/sql/text-writes.ts";

const written = (sql: string): Record<string, string[]> =>
  Object.fromEntries(
    [...computedWrites(sql)].map(([table, columns]) => [
      table,
      [...columns].toSorted(),
    ]),
  );

describe("computedWrites", () => {
  it("lists the columns an insert, update or upsert computes a value for", () => {
    expect(
      written(`
create function f(p_kind text, p_name text) returns void language plpgsql as $$
begin
  insert into "app"."tags" ("kind", "name", "status", "note")
  values (p_kind, f.p_name, 'active', null)
  on conflict ("kind") do update set "name" = excluded."name", "note" = coalesce(f.p_name, 'x');
  update "app"."tags" t set "status" = 'archived', "slug" = lower(p_name) where t."kind" = p_kind;
  insert into app.runs (kind, status) select p_kind, 'queued' from app.tags where true;
end;
$$;`),
    ).toEqual({
      "app.runs": ["kind"],
      "app.tags": ["kind", "name", "note", "slug"],
    });
  });

  it("treats literals, null, default and copies of the same column as safe", () => {
    expect(
      written(`insert into public.items (status, label, kind) values ('done', default, null)
on conflict (id) do update set status = excluded.status, kind = 'x';
-- update public.items set status = p_status;`),
    ).toEqual({});
  });
});
