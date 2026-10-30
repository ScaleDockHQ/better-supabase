import { describe, expect, it } from "vitest";

import type { SubjectsConfig } from "../../../src/config/index.ts";
import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const SUBJECTS: SubjectsConfig = {
  patient: {
    table: "public.patients",
    title: "name",
    permissions: { read: "patients.read" },
    team: { actions: ["read", "write"] },
  },
  invoice: { table: "public.invoices", permissions: { read: "invoices.read" } },
};

const render = (
  blocks: readonly string[],
  layout: BlockSqlLayout = {},
): ReturnType<typeof renderBlocks> =>
  renderBlocks(blocks, { subjects: SUBJECTS, ...layout });

const sqlOf = (
  files: ReturnType<typeof renderBlocks>,
  module = "subjects",
): string =>
  files
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("record teams", () => {
  it("ORs the team into a keyed action and grants a team-only action", () => {
    const sql = sqlOf(render(["subjects"]));

    expect(sql).toContain(
      `when 'read' then (coalesce(better_supabase.can('tenant', s."organization_id", 'patients.read'), false) or "better_supabase"."is_subject_member"('patient', s."id"::text))`,
    );
    expect(sql).toContain(
      `when 'write' then "better_supabase"."is_subject_member"('patient', s."id"::text)`,
    );
    expect(sql).not.toContain(`is_subject_member"('invoice'`);
  });

  it("checks the team in can_subject_for with the member's dates", () => {
    const sql = sqlOf(render(["subjects"]));

    expect(sql).toMatch(
      /where m\."subject_type" = 'patient'\s+and m\."subject_id" = s\."id"::text\s+and m\."tenant_id" = s\."organization_id"\s+and \(m\."user_id" = can_subject_for\.member\)/u,
    );
    expect(sql).toContain(
      `(m."ends_on" is null or m."ends_on" >= current_date)`,
    );
  });

  it("writes the table, the policy and the functions", () => {
    const sql = sqlOf(render(["subjects"]));

    expect(sql).toContain(
      `create table if not exists "better_supabase"."subject_members"`,
    );
    expect(sql).toContain(`check (("user_id" is null) <> ("team_id" is null))`);
    expect(sql).toContain(
      `create policy subject_members_read on "better_supabase"."subject_members"`,
    );
    expect(sql).toContain(
      `create or replace function "better_supabase"."add_subject_member"(subject_type text, subject_id text, user_id uuid default null, team_id uuid default null, role text default 'member', starts_on date default null, ends_on date default null)`,
    );
    expect(sql).toContain(
      `create or replace function "better_supabase"."my_subjects"(tenant uuid, subject_type text default null, page_size integer default 100, cursor text default null)`,
    );
    expect(sql).toContain("array['patient']::text[]");
    expect(sql).toContain("'{lead,member}'::text[]");
    expect(sql).toContain("hint = 'SUBJECT_MEMBER_FORBIDDEN'");
  });

  it("reads team memberships through the teams block when it is installed", () => {
    const sql = sqlOf(render(["teams", "subjects"]));

    expect(sql).toContain(
      `references "better_supabase"."teams" ("id") on delete cascade`,
    );
    expect(sql).toContain(
      `m."team_id" in (select "better_supabase"."team_ids_of"(auth.uid()))`,
    );
    expect(sql).toMatch(
      /exists \(\s+select 1 from "better_supabase"\."team_members" tm/u,
    );
    expect(sqlOf(render(["subjects"]))).not.toContain("team_ids_of");
  });

  it("takes the roles from the recordTeam option", () => {
    const sql = sqlOf(
      render(["subjects"], {
        modules: {
          subjects: { options: { recordTeam: { roles: ["owner", "viewer"] } } },
        },
      }),
    );

    expect(sql).toContain("'{owner,viewer}'::text[]");
    expect(() =>
      render(["subjects"], {
        modules: { subjects: { options: { recordTeam: { roles: ["Lead"] } } } },
      }),
    ).toThrow(/recordTeam\.roles must be a non-empty list/u);
  });

  it("refuses a team on a type without a tenant or with bad actions", () => {
    const bad = (subjects: SubjectsConfig) => () =>
      renderBlocks(["subjects"], { subjects });

    expect(
      bad({
        note: { table: "notes", tenant: false, team: { actions: ["read"] } },
      }),
    ).toThrow(/team needs a tenant column/u);
    expect(bad({ note: { table: "notes", team: { actions: [] } } })).toThrow(
      /team must be \{ actions/u,
    );
  });

  it("limits the represents target to the types with a team", () => {
    const relations = sqlOf(
      render(["contacts", "relations", "subjects"]),
      "relations",
    );

    expect(relations).toContain(
      `if v_kind = 'represents' and not (v_source_type in ('person') and v_target_type in ('patient')) then`,
    );
  });
});
