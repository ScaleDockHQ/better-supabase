import { describe, expect, it } from "vitest";

import { classifyDrift, driftSummary } from "../../../src/cli/sql/drift.ts";

const BASE = [
  'create function "x"."note_subject_readable"(a uuid) returns boolean as $$',
  "  return case subject_type",
  "    when 'task' then true",
  "  end;",
  "create trigger note_search before insert on notes;",
  "select 1;",
].join("\n");

describe("classifyDrift", () => {
  it("calls a new subject case a subjects drift", () => {
    const next = BASE.replace(
      "    when 'task' then true",
      "    when 'task' then true\n    when 'quote' then true",
    );

    expect(classifyDrift(BASE, next)).toBe("subjects");
  });

  it("calls a lost search trigger a search drift", () => {
    const next = BASE.replace(
      "create trigger note_search before insert on notes;\n",
      "",
    );

    expect(classifyDrift(next, BASE)).toBe("search");
  });

  it("calls any other changed line an other drift", () => {
    expect(classifyDrift(BASE, BASE.replace("select 1;", "select 2;"))).toBe(
      "other",
    );
  });

  it("treats a missing file as other", () => {
    expect(classifyDrift(undefined, BASE)).toBe("other");
  });
});

describe("driftSummary", () => {
  it("names each kind that has files", () => {
    expect(
      driftSummary({ subjects: ["a", "b"], search: [], other: ["c"] }),
    ).toBe(
      "Drift: 2 differ only in subject cases (a block was added or removed; `upgrade` writes them); 1 differ in other lines.",
    );
  });

  it("is undefined without drift", () => {
    expect(
      driftSummary({ subjects: [], search: [], other: [] }),
    ).toBeUndefined();
  });
});
