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
      `join "public"."customer_search" f on f."customer_id" = s."id"`,
    );
    expect(sql).toContain(
      `and f."customer_id" = (search_refresh.subject_id)::uuid`,
    );
    expect(sql).not.toContain(`f."customer_id"::text`);
    expect(sql).toContain(`f."vat"::text`);
    expect(sql).toContain(
      `and (f."archived_at" is null or f."archived_at"::text = 'false')`,
    );
    expect(sql).toContain(`'description', v.description,`);
    expect(sql).toContain(
      `alter table "better_supabase"."search_documents" add column "description" text;`,
    );
    expect(sql).toContain(
      `create trigger "bsb_search_customer_watch_0" after insert or delete on "public"."customer_contacts"`,
    );
    expect(sql).toContain(
      `create trigger "bsb_search_customer_watch_0_u" after update of "customer_id" on "public"."customer_contacts"`,
    );
    expect(sql).toContain(
      `when (old."customer_id" is distinct from new."customer_id")`,
    );
  });

  it("creates watch triggers without a do block and limits them to named columns", () => {
    const sql = sqlOf();

    expect(sql).not.toContain("$watch$");
    expect(sql).toContain(
      'perform "better_supabase"."search_enqueue"(\'customer\', new."customer_id"::text);',
    );

    const columns = sqlOf({
      customer: {
        table: "public.customers",
        title: "name",
        search: {
          watch: [
            { table: "public.tags", key: "customer_id", columns: ["label"] },
          ],
        },
      },
    });

    expect(columns).toContain(
      'after update of "customer_id", "label" on "public"."tags"',
    );
    expect(columns).toContain(
      'when (old."customer_id" is distinct from new."customer_id" or old."label" is distinct from new."label")',
    );
  });

  it("notes keys while an import defers indexing and indexes each once", () => {
    const sql = sqlOf();

    expect(sql).toContain("better_supabase.search_deferred");
    expect(sql).toContain("better_supabase.search_dirty_");
    expect(sql).toContain("search_refresh_dirty");
    expect(sql).toContain("is distinct from (excluded");
  });

  it("follows a watched table across a junction table to the records", () => {
    const sql = sqlOf({
      customer: {
        table: "public.customers",
        idType: "uuid",
        title: "name",
        search: {
          body: ["tag_names"],
          from: { view: "public.customer_search", key: "customer_id" },
          watch: [
            {
              table: "public.tags",
              key: "id",
              through: [
                {
                  table: "public.customer_tags",
                  from: "tag_id",
                  to: "customer_id",
                },
              ],
            },
            {
              table: "public.regions",
              key: "id",
              via: "account_id",
              through: [
                { table: "public.accounts", from: "region_id", to: "id" },
              ],
            },
          ],
        },
      },
    });

    expect(sql).toContain(
      `for v_id in select v.value::text from (select h0."customer_id" from "public"."customer_tags" h0 where h0."tag_id" in (select new."id")) v(value) loop`,
    );
    expect(sql).toContain(
      `where s."account_id" in (select h0."id" from "public"."accounts" h0 where h0."region_id" in (select old."id"))`,
    );

    const untyped = sqlOf({
      customer: {
        table: "public.customers",
        title: "name",
        search: {
          from: { view: "public.customer_search", key: "customer_id" },
        },
      },
    });

    expect(untyped).toContain(
      `join "public"."customer_search" f on f."customer_id"::text = s."id"::text`,
    );

    expect(() =>
      sqlOf({
        customer: {
          table: "public.customers",
          search: {
            watch: [
              {
                table: "public.tags",
                key: "id",
                through: [
                  { table: "public.customer_tags", from: "x;y", to: "id" },
                ],
              },
            ],
          },
        },
      }),
    ).toThrow(/through\[0\]\.from/u);
  });

  it("re-indexes a record read through a view on a change to any of its columns", () => {
    expect(sqlOf()).toContain(
      `after insert or delete or update on "public"."customers"`,
    );
    expect(
      sqlOf({
        customer: {
          table: "public.customers",
          title: "name",
          search: { body: ["vat"] },
        },
      }),
    ).toContain(
      `after insert or delete or update of "id", "organization_id", "name", "vat" on "public"."customers"`,
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

  it("keeps a text comparison when the two key types are known to differ", () => {
    const sql = renderBlocks(["search"], {
      subjects: {
        customer: {
          table: "public.customers",
          idType: "uuid",
          title: "name",
          search: {
            from: { view: "public.customer_search", key: "customer_id" },
          },
        },
      },
      appColumns: {
        "public.customer_search": [{ name: "customer_id", type: "text" }],
      },
    })
      .filter((file) => file.module === "search")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(`f."customer_id"::text = s."id"::text`);
    expect(sql).toContain(
      "customer search.from compares text with uuid, so the comparison stays text.",
    );
  });
});
