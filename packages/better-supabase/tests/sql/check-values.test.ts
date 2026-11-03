import { describe, expect, it } from "vitest";

import {
  checkValues,
  declaredCheckValues,
} from "../../src/sql/check-values.ts";

describe("checkValues", () => {
  it("reads an in list as a schema file writes it", () => {
    expect(checkValues("check (status in ('pending', 'sent'))")).toEqual({
      column: "status",
      values: ["pending", "sent"],
    });
  });

  it("reads an array as Postgres prints it", () => {
    expect(
      checkValues(
        "CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text])))",
      ),
    ).toEqual({ column: "status", values: ["pending", "sent"] });
  });

  it("reads a varchar array with its casts", () => {
    expect(
      checkValues(
        "CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'sent'::character varying])::text[])))",
      ),
    ).toEqual({ column: "status", values: ["pending", "sent"] });
  });

  it("reads a check Postgres prints as not valid", () => {
    expect(
      checkValues(
        "CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text]))) NOT VALID",
      ),
    ).toEqual({ column: "status", values: ["pending", "sent"] });
  });

  it("reads a single value", () => {
    expect(checkValues("CHECK ((status = 'pending'::text))")).toEqual({
      column: "status",
      values: ["pending"],
    });
  });

  it("unescapes a quote", () => {
    expect(checkValues("check (status in ('it''s'))")).toEqual({
      column: "status",
      values: ["it's"],
    });
  });

  it("leaves a check on several columns, a negation or an expression", () => {
    expect(
      checkValues(
        "CHECK (((status = ANY (ARRAY['pending'::text])) AND (channel = 'email'::text)))",
      ),
    ).toBeUndefined();
    expect(
      checkValues(
        "CHECK ((status <> ALL (ARRAY['pending'::text, 'sent'::text])))",
      ),
    ).toBeUndefined();
    expect(checkValues("CHECK ((length(status) > 0))")).toBeUndefined();
  });
});

describe("declaredCheckValues", () => {
  it("reads the inline and table checks of a create table", () => {
    const sql = `
create table public.jobs (
  id uuid primary key,
  status text not null check (status in ('pending', 'running')),
  kind text,
  constraint jobs_kind_check check (kind in ('batch', 'single'))
);
`;

    expect(declaredCheckValues([{ text: sql }])).toEqual([
      {
        table: "public.jobs",
        column: "status",
        values: ["pending", "running"],
      },
      { table: "public.jobs", column: "kind", values: ["batch", "single"] },
    ]);
  });

  it("keeps the tables in the schemas it is given", () => {
    const sql = `
create table public.jobs (status text check (status in ('pending')));
create table other.jobs (status text check (status in ('pending')));
`;

    expect(declaredCheckValues([{ text: sql }], ["public"])).toEqual([
      { table: "public.jobs", column: "status", values: ["pending"] },
    ]);
  });
});
