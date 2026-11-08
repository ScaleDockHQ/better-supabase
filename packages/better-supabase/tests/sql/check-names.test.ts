import { describe, expect, it } from "vitest";

import {
  bsbCheckNames,
  bsbConstraintName,
} from "../../src/sql/policy-names.ts";

describe("bsbConstraintName", () => {
  it("prefixes a name once and shortens one past 63 bytes with a hash", () => {
    expect(bsbConstraintName("t_a_check")).toBe("bsb_t_a_check");
    expect(bsbConstraintName("bsb_t_a_check")).toBe("bsb_t_a_check");
    expect(bsbConstraintName(`${"a".repeat(70)}_check`)).toHaveLength(63);
  });
});

describe("bsbCheckNames", () => {
  it("names a column check after its table and column, as Postgres would", () => {
    expect(
      bsbCheckNames(
        `create table "s"."t" ("a" int not null check ("a" > 0), "b" int);`,
      ),
    ).toBe(
      `create table "s"."t" ("a" int not null constraint bsb_t_a_check check ("a" > 0), "b" int);`,
    );
  });

  it("names a check that reads two columns or none after the table, and numbers a clash", () => {
    const sql = bsbCheckNames(
      `create table t (a int check (a > 0), b int, check (a < b), check (a <> b), c int check (a > 1), d int check (true));`,
    );

    expect(sql).toContain("constraint bsb_t_a_check check (a > 0)");
    expect(sql).toContain("constraint bsb_t_check check (a < b)");
    expect(sql).toContain("constraint bsb_t_check1 check (a <> b)");
    expect(sql).toContain("constraint bsb_t_a_check1 check (a > 1)");
    expect(sql).toContain("constraint bsb_t_check2 check (true)");
  });

  it("names the checks of add column and add check", () => {
    const sql = bsbCheckNames(
      `alter table s.t add column c int check ("c" > 0), add check ("c" < 5);`,
    );

    expect(sql).toContain("add column c int constraint bsb_t_c_check check");
    expect(sql).toContain("constraint bsb_t_c_check1 check");
  });

  it("prefixes a named check where it is added, dropped, validated and tested", () => {
    const sql =
      bsbCheckNames(`alter table t drop constraint if exists t_a_check;
alter table t add constraint t_a_check check (a > 0) not valid;
alter table t validate constraint t_a_check;
select 1 from pg_constraint where conname = 't_a_check';`);

    expect(sql).not.toMatch(/(?<!bsb_)t_a_check/);
    expect(sql.match(/bsb_t_a_check/g)).toHaveLength(4);
  });

  it("keeps a drop of a check the text never adds, a policy check and a comment", () => {
    const sql = `-- create table x (a int check (a > 0));
alter table t drop constraint if exists legacy_check;
create policy p on t using (true) with check (a > 0);`;

    expect(bsbCheckNames(sql)).toBe(sql);
  });
});
