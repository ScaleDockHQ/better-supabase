import { describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../../src/sql/module-types.ts";

import { renderModules } from "../../../src/sql/render.ts";

const subjects: ModuleLayout["subjects"] = {
  task: {
    table: "app.tasks",
    title: "name",
    url: "/tasks/{id}?board={board_id}",
    deletedAt: "deleted_at",
    search: { body: ["description", "notes"] },
  },
  doc: { table: "app.docs", search: { title: "heading" } },
  label: { table: "app.labels", title: "name", tenant: false, search: {} },
  plain: { table: "app.plain", title: "name" },
};

const render = (layout: ModuleLayout, names: readonly string[] = ["search"]) =>
  renderModules(names, layout).filter((file) => file.module === "search");

const sqlOf = (layout?: ModuleLayout, names?: readonly string[]) =>
  render(layout ?? { subjects }, names)
    .map((file) => file.contents)
    .join("\n");

describe("search module", () => {
  it("indexes each searched subject through a trigger on its columns", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      `after insert or delete or update of "id", "organization_id", "name", "description", "notes", "deleted_at", "board_id" on "app"."tasks"`,
    );
    expect(sql).toContain(
      `execute function "better_supabase"."search_index_row"('task', 'id')`,
    );
    expect(sql).toContain(`create trigger "bs_search_doc_index"`);
    expect(sql).not.toContain("bs_search_label_index");
    expect(sql).not.toContain("bs_search_plain_index");
    expect(sql).toContain(
      `nullif(concat_ws(E'\\n', s."description"::text, s."notes"::text), '')`,
    );
    expect(sql).toContain(`and s."deleted_at" is null;`);
    expect(sql).toContain("'/tasks/' ||");
    expect(sql).toContain(
      `select s."organization_id", s."heading"::text, null, null`,
    );
  });

  it("searches as the caller with websearch, prefixes and trigrams", () => {
    const sql = sqlOf();
    expect(sql).toContain("security invoker");
    expect(sql).toContain("websearch_to_tsquery('simple', v_norm)");
    expect(sql).toContain("quote_literal(w) || ':*'");
    expect(sql).toContain("operator(extensions.%) v_norm");
    expect(sql).toContain(
      `"better_supabase"."can_subject"(f.subject_type, f.subject_id, 'read')`,
    );
    expect(sql).toContain("better_supabase.tenant_ids_with('search.read')");
    expect(sql).not.toContain("vector_hits");
  });

  it("reads recents and favorites from share-links when it is installed", () => {
    expect(sqlOf()).toContain(
      "select null::text, null::text, null::timestamptz, null::timestamptz where false",
    );
    const sql = sqlOf({ subjects }, ["share-links", "search"]);
    expect(sql).toContain(`from "better_supabase"."subject_user_state" s`);
    expect(sql).toContain(
      `insert into "better_supabase"."subject_user_state" as st`,
    );
  });

  it("keeps embeddings and fuses ranks with vector-search and dimensions", () => {
    const sql = sqlOf(
      {
        subjects,
        modules: {
          search: { options: { dimensions: 384, config: "english" } },
        },
      },
      ["vector-search", "search"],
    );
    expect(sql).toContain(
      `alter table "better_supabase"."search_documents" add column if not exists "embedding" "extensions".vector(384);`,
    );
    expect(sql).toContain("vector_hits as materialized");
    expect(sql).toContain("coalesce(1.0 / (60 + t.rank), 0)");
    expect(sql).toContain("search_set_embedding");
    expect(sql).toContain("to_tsvector('english'");
    expect(sql).toContain(
      `"embedding" = case when "better_supabase"."search_documents"."content_hash" = excluded."content_hash"`,
    );
    expect(
      sqlOf({
        subjects,
        modules: { search: { options: { dimensions: 384 } } },
      }),
    ).not.toContain("vector_hits");
  });

  it("reindexes in the data file, only when a subject is searched", () => {
    const data = (layout: ModuleLayout) =>
      render(layout)
        .filter((file) => file.kind === "data")
        .map((file) => file.contents)
        .join("");
    expect(data({ subjects })).toContain(
      `select "better_supabase"."search_reindex"();`,
    );
    expect(data({})).not.toContain("search_reindex");
  });

  it("rejects a bad config or dimensions", () => {
    expect(() =>
      sqlOf({
        subjects,
        modules: { search: { options: { config: "en glish" } } },
      }),
    ).toThrow("options.config must be a text search configuration");
    expect(() =>
      sqlOf({
        subjects,
        modules: { search: { options: { dimensions: 1.5 } } },
      }),
    ).toThrow("options.dimensions must be the embedding size");
  });

  it("renders nothing in custom mode, and no table when adopting", () => {
    expect(
      sqlOf({ subjects, modules: { search: { mode: "custom" } } }),
    ).not.toContain("search_refresh");
    const adopted = sqlOf({
      subjects,
      modules: {
        search: { mode: "adopt", tables: { documents: "app.search_index" } },
      },
    });
    expect(adopted).not.toContain('"better_supabase"."search_documents"');
    expect(adopted).toContain(`from "app"."search_index" d`);
  });
});
