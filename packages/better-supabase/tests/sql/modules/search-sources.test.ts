import { describe, expect, it } from "vitest";

import type { SubjectsConfig } from "../../../src/config/index.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const SUBJECTS: SubjectsConfig = {
  customer: {
    table: "public.customers",
    idType: "uuid",
    title: "name",
    search: {
      title: "name",
      body: ["people"],
      description: "vat",
      exclude: "archived_at",
      from: { view: "public.customer_search", key: "customer_id" },
      watch: [{ table: "public.customer_contacts", key: "customer_id" }],
    },
  },
};

const sqlOf = (subjects: SubjectsConfig = SUBJECTS): string =>
  renderBlocks(["search"], { subjects })
    .filter((file) => file.module === "search")
    .map((file) => file.contents)
    .join("\n");

describe("search sources beyond the record's row", () => {
  it("reads a source view, returns a description, leaves excluded rows out and watches related tables", () => {
    const sql = sqlOf();

    expect(sql).toContain(
      `join "public"."customer_search" f on f."customer_id"::text = s."id"::text`,
    );
    expect(sql).toContain(`f."vat"::text`);
    expect(sql).toContain(
      `and (f."archived_at" is null or f."archived_at"::text = 'false')`,
    );
    expect(sql).toContain(`'description', v.description,`);
    expect(sql).toContain(
      `alter table "better_supabase"."search_documents" add column if not exists "description" text;`,
    );
    expect(sql).toContain(
      `create trigger "bsb_search_customer_watch_0" after insert or update or delete on "public"."customer_contacts"`,
    );
  });

  it("leaves the index as it was without the new keys", () => {
    const sql = sqlOf({
      customer: {
        table: "public.customers",
        title: "name",
        search: { body: ["vat"] },
      },
    });

    expect(sql).not.toContain("description");
    expect(sql).not.toContain("_watch_");
  });

  it("refuses a source or watched table that is no table name", () => {
    expect(() =>
      sqlOf({
        customer: {
          table: "public.customers",
          title: "name",
          search: { from: { view: "x;y", key: "id" } },
        },
      }),
    ).toThrow(/search\.from\.view/u);
    expect(() =>
      sqlOf({
        customer: {
          table: "public.customers",
          title: "name",
          search: { watch: [{ table: "public.contacts", key: "bad key" }] },
        },
      }),
    ).toThrow(/search\.watch\[0\]\.key/u);
  });
});
