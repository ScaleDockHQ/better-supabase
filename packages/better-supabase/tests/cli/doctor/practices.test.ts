import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { PRACTICE_RULES } from "../../../src/cli/doctor/practices.ts";

const codes = (sql: string, path = "supabase/schemas/app.sql"): string[] => {
  // SAFETY: the rules read only `sqlFiles`.
  const context = {
    sqlFiles: [{ path, text: sql }],
  } as unknown as DoctorContext;

  return PRACTICE_RULES.flatMap((rule) =>
    (rule.check(context) as unknown[]).map(() => rule.code),
  );
};

describe("practice rules over the app's schema files", () => {
  it("BS365 flags an update policy without a select policy", () => {
    expect(
      codes(
        `create policy "u" on public.notes for update to authenticated using (true);`,
      ),
    ).toEqual(["BS365"]);
  });

  it("BS365 accepts a select or all policy on the same table", () => {
    expect(
      codes(`create policy "u" on public.notes for update using (true);
create policy "s" on public.notes for select using (true);`),
    ).toEqual([]);
    expect(
      codes(`create policy "a" on public.notes for all using (true);
create policy "u" on public.notes for update using (true);`),
    ).toEqual([]);
  });

  it("BS366 flags user_metadata in a policy", () => {
    expect(
      codes(
        `create policy "s" on public.notes for select using ((select auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');`,
      ),
    ).toEqual(["BS366"]);
  });

  it("BS367 flags a view without security_invoker", () => {
    expect(codes("create view public.v as select 1;")).toEqual(["BS367"]);
    expect(
      codes("create view public.v with (security_invoker = true) as select 1;"),
    ).toEqual([]);
  });

  it("BS368 flags timestamp and serial columns", () => {
    expect(
      codes("create table public.t (id serial primary key, at timestamp);"),
    ).toEqual(["BS368"]);
    expect(
      codes(
        "create table public.t (id int generated always as identity, at timestamptz);",
      ),
    ).toEqual([]);
  });

  it("skips migrations and files the blocks wrote", () => {
    const sql = "create view public.v as select 1;";

    expect(codes(sql, "supabase/migrations/20260101000000_x.sql")).toEqual([]);
    expect(codes(`-- @bsb-block tags\n${sql}`)).toEqual([]);
  });
});
