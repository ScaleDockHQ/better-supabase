import { describe, expect, it } from "vitest";

import {
  canonicalKey,
  canonicalSql,
} from "../../../src/cli/schema-reader/index.ts";

describe("canonicalSql", () => {
  it("gives one text for spacing, comments, keyword case and quoting", async () => {
    const a = await canonicalSql(
      '-- note\nCREATE  TABLE "public"."t" (\n  id INT  PRIMARY KEY\n);',
    );

    const b = await canonicalSql("create table public.t (id int primary key)");

    expect(a).toBeDefined();
    expect(a).toBe(b);
  });

  it("keeps a difference in meaning", async () => {
    expect(await canonicalSql("select 'A';")).not.toBe(
      await canonicalSql("select 'a';"),
    );
  });

  it("reads CRLF and LF text as the same statements", async () => {
    expect(await canonicalSql("select 1;\r\nselect 2;\r\n")).toBe(
      await canonicalSql("select 1;\nselect 2;\n"),
    );
  });

  it("returns an empty text for a comment-only file and undefined for a syntax error", async () => {
    expect(await canonicalSql("-- nothing\n")).toBe("");
    expect(await canonicalSql("selec 1;")).toBeUndefined();
  });
});

describe("canonicalKey", () => {
  it("falls back to collapsed text for a statement that does not parse", async () => {
    expect(await canonicalKey("selec   1 ;")).toBe("selec 1");
  });
});
