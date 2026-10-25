import { describe, expect, it } from "vitest";

import { isSqlType } from "../../src/config/sql-type.ts";

describe("isSqlType", () => {
  it.each([
    "text",
    "text not null default 'en'",
    "jsonb not null default '{}'",
    "uuid[] default '{}'::uuid[]",
    "text[] not null default '{a,b}'",
    "numeric(12, 2) default 0",
    'jsonb default \'{"tier": "free"}\'',
    "timestamptz default '2026-01-01 00:00:00+00'::timestamptz",
    "text default 'it''s'",
    "varchar(20) unique",
  ])("accepts %s", (type) => {
    expect(isSqlType(type)).toBe(true);
  });

  it.each([
    "",
    "1text",
    "text; drop table users",
    "text default ''; drop table users; --'",
    "text -- comment",
    "text /* comment */",
    "text default 'unclosed",
    "text default 'a' || 'b'",
    "text default x:y",
    "text default 'a'::text:",
    "text{}",
    "text default $$x$$",
  ])("refuses %s", (type) => {
    expect(isSqlType(type)).toBe(false);
  });
});
