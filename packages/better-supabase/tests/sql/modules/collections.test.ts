import { describe, expect, it } from "vitest";

import type { SubjectsConfig } from "../../../src/config/types/subjects.ts";

import { renderModules } from "../../../src/sql/render.ts";

const SUBJECTS: SubjectsConfig = {
  company: { table: "public.companies", idType: "uuid", cascade: true },
  deal: { table: "public.deals" },
  note: { table: "public.notes", tenant: false },
};

const sqlOf = (
  extra: readonly string[] = [],
  subjects: SubjectsConfig = SUBJECTS,
): string =>
  renderModules(["collections", ...extra], { subjects })
    .filter((file) => file.module === "collections")
    .map((file) => file.contents)
    .join("\n");

describe("collections module", () => {
  it("creates lists, entries and favorites with read policies", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."subject_collections"',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."subject_collection_entries"',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."favorites"',
    );
    expect(sql).toContain("create policy subject_collection_entries_read");
    expect(sql).toContain(
      `"better_supabase"."can_subject"("subject_type", "subject_id", 'read')`,
    );
    expect(sql).toContain('"owner_id" = (select auth.uid())');
  });

  it("accepts only registered subject types with a tenant", () => {
    const sql = sqlOf();
    expect(sql).toContain("'{company,deal}'::text[]");
    expect(sql).toContain(
      `when 'company' then exists (select 1 from "public"."companies" s where s."id" = (v_id)::uuid`,
    );
  });

  it("cascades entries and stars of a deleted record when the registry asks", () => {
    const sql = sqlOf();
    expect(sql).toContain("bs_collections_company_cascade");
    expect(sql).not.toContain("bs_collections_deal_cascade");
    expect(sql).toContain(
      `delete from "better_supabase"."favorites" where "subject_type" = v_type`,
    );
  });

  it("checks team membership only with the teams module", () => {
    expect(sqlOf()).toContain("not (v_service or false)");
    expect(sqlOf(["teams"])).toContain('"team_ids_of"((select auth.uid()))');
  });

  it("records its events with outbox installed", () => {
    const sql = sqlOf(["outbox"]);

    for (const type of [
      "collection.created",
      "collection.archived",
      "collection.entry_added",
      "collection.entry_removed",
    ]) {
      expect(sql).toContain(`'${type}'`);
    }
  });

  it("renders nothing in custom mode", () => {
    const sql = renderModules(["collections"], {
      modules: { collections: { mode: "custom" } },
    })
      .filter((file) => file.module === "collections")
      .map((file) => file.contents)
      .join("");

    expect(sql).not.toContain("create_collection");
  });

  it("refuses every subject without a registry", () => {
    const sql = sqlOf([], {});
    expect(sql).toContain("'{}'::text[]");
    expect(sql).not.toContain("_cascade");
  });
});
