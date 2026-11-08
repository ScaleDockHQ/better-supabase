import { describe, expect, it } from "vitest";

import { bsbPolicyName, bsbPolicyNames } from "../../src/sql/policy-names.ts";

describe("bsbPolicyName", () => {
  it("prefixes a name once", () => {
    expect(bsbPolicyName("tasks_read")).toBe("bsb_tasks_read");
    expect(bsbPolicyName("bsb_tasks_read")).toBe("bsb_tasks_read");
  });

  it("shortens a name past 63 bytes with a hash that keeps two names apart", () => {
    const long = `${"a".repeat(70)}_read`;
    const other = `${"a".repeat(70)}_write`;

    expect(bsbPolicyName(long)).toHaveLength(63);
    expect(bsbPolicyName(long)).not.toBe(bsbPolicyName(other));
  });
});

describe("bsbPolicyNames", () => {
  it("renames the create and the drop of one policy, in quotes or not", () => {
    const sql = `drop policy if exists tasks_read on t;
create policy "tasks_read" on t for select using (true);
alter policy tasks_read on t rename to x;`;

    expect(bsbPolicyNames(sql)).toBe(`drop policy if exists bsb_tasks_read on t;
create policy bsb_tasks_read on t for select using (true);
alter policy bsb_tasks_read on t rename to x;`);
  });

  it("keeps a drop of a policy the text never creates", () => {
    const sql = "drop policy if exists legacy_read on t;";

    expect(bsbPolicyNames(sql)).toBe(sql);
  });

  it("ignores a statement inside a comment or a string", () => {
    const sql = `-- create policy a_read on t;
select 'create policy b_read on t';`;

    expect(bsbPolicyNames(sql)).toBe(sql);
  });
});
