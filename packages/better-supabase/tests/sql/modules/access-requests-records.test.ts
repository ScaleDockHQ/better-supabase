import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { SubjectsConfig } from "../../../src/config/index.ts";
import type { BlockContributes } from "../../../src/sql/contributions.ts";
import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { SQL_MODULES } from "../../../src/sql/registry.ts";
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

const BLOCKS = ["access-requests", "subjects", "notifications"];

const sqlOf = (
  layout: BlockSqlLayout = {},
  blocks: readonly string[] = BLOCKS,
  module = "access-requests",
): string =>
  renderBlocks(blocks, { subjects: SUBJECTS, ...layout })
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const withOptions = (options: Record<string, unknown>): BlockSqlLayout => ({
  modules: { "access-requests": { options } },
});

describe("record access requests", () => {
  it("renders the record functions over the types with a team", () => {
    const sql = sqlOf();

    expect(sql).toContain(
      `create or replace function "better_supabase"."request_record_access"(subject_type text, subject_id text, action text default 'read', reason text default null, duration interval default interval '7 days')`,
    );
    expect(sql).toContain("array['patient']::text[]");
    expect(sql).toContain(
      "when 'patient' then not (request_record_access.action = any (array['read', 'write']::text[]))",
    );
    expect(sql).not.toContain("'invoice'");
    expect(sql).toContain(
      `jsonb_build_object('permission', 'subjects.manage')`,
    );
    expect(sql).toContain(
      `v_member := "better_supabase"."grant_subject_member"(`,
    );
    expect(sql).toContain(
      `perform "better_supabase"."close_subject_member"(v_row."member_id");`,
    );
    expect(sql).toContain(`interval '8 hours'`);
    expect(sql).toContain("'permission', 'access_requests.review'");
    expect(sql).toContain("ACCESS_REQUEST_REASON_REQUIRED");
    expect(sql).toContain("ACCESS_REQUEST_REVIEW_INVALID");
    expect(sql).toContain(
      `alter table "better_supabase"."access_requests" alter column "role" drop not null;`,
    );
    expect(sql).toContain(`and r."target" = 'role'`);
  });

  it("adds ends_at to subject_members and checks it", () => {
    const sql = sqlOf({}, BLOCKS, "subjects");

    expect(sql).toContain(`"ends_at" timestamptz,`);
    expect(sql).toContain(
      `alter table "better_supabase"."subject_members" add column if not exists "ends_at" timestamptz;`,
    );
    expect(sql).toContain(`and (m."ends_at" is null or m."ends_at" > now())`);
    expect(sql).toContain(`'endsAt', m."ends_at"`);
    expect(sql).toContain(
      `revoke execute on function "better_supabase"."grant_subject_member"(text, text, uuid, timestamptz, boolean, text) from public, anon, authenticated;`,
    );
  });

  it("leaves records out over a team table without ends_at", () => {
    const layout: BlockSqlLayout = {
      modules: { subjects: { columns: { members: { endsAt: null } } } },
    };

    const subjects = sqlOf(layout, BLOCKS, "subjects");
    expect(subjects).not.toContain("ends_at");
    expect(subjects).not.toContain("grant_subject_member");
    expect(sqlOf(layout)).not.toContain("request_record_access");
  });

  it("finds leads through teams when teams is installed", () => {
    const sql = sqlOf({}, [...BLOCKS, "teams"], "subjects");

    expect(sql).toContain(
      `join "better_supabase"."team_members" tm on tm."team_id" = m."team_id"`,
    );
  });

  it("renders nothing for records without subjects or in custom mode", () => {
    const alone = sqlOf({}, ["access-requests", "outbox"]);
    expect(alone).not.toContain("request_record_access");
    expect(alone).toContain(
      `'target', 'role', 'subjectType', null::text, 'subjectId', null::text, 'action', null::text`,
    );
    expect(alone).toContain(`"role" text not null check`);

    const custom = sqlOf({ modules: { subjects: { mode: "custom" } } });
    expect(custom).not.toContain("request_record_access");
  });

  it("refuses every record when no type has a team", () => {
    const sql = renderBlocks(BLOCKS, {
      subjects: { invoice: SUBJECTS["invoice"]! },
    })
      .filter((file) => file.module === "access-requests")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("array[]::text[]");
    expect(sql).toContain("or true then");
  });

  it("caps the default duration and takes the emergency hours", () => {
    const sql = sqlOf(
      withOptions({ maxDuration: "P1D", emergency: { maxHours: 2 } }),
    );

    expect(sql).toContain(
      "coalesce(request_record_access.duration, least(interval '7 days', 'P1D'::interval))",
    );
    expect(sql).toContain(`interval '2 hours'`);
    expect(sqlOf(withOptions({ emergency: {} }))).toContain(
      `interval '8 hours'`,
    );
  });

  it("rejects a bad emergency option", () => {
    for (const emergency of [
      "8",
      null,
      { maxHours: 0 },
      { maxHours: 1.5 },
      { maxHours: 200 },
      { maxHours: "8" },
      { hours: 8 },
    ]) {
      expect(() => sqlOf(withOptions({ emergency }))).toThrow(
        "emergency must be { maxHours }",
      );
    }
  });

  describe("an accessGrant contribution", () => {
    const tags = SQL_MODULES["tags"];
    const original = tags?.contributes;

    const contribute = (
      grants: readonly { subject: string; grant: string }[],
    ): void => {
      const contributes: BlockContributes = {
        ...original,
        "access-requests": () => grants,
      };

      Reflect.set(tags ?? {}, "contributes", contributes);
    };

    beforeEach(() => {
      contribute([{ subject: "patient", grant: "app.grant_patient_access" }]);
    });

    afterEach(() => {
      Reflect.set(tags ?? {}, "contributes", original);
    });

    it("grants through the contributed function instead of a team row", () => {
      const sql = sqlOf({}, [...BLOCKS, "tags"]);

      expect(sql).toContain(
        `when 'patient' then
      perform app.grant_patient_access(v_row."subject_id", v_row."user_id", v_row."action", v_ends);`,
      );
      expect(sql).toContain(
        `perform app.grant_patient_access(v_row."subject_id", v_row."user_id", v_row."action", now());`,
      );
    });

    it("needs a team on the subject and one grant per subject", () => {
      contribute([{ subject: "invoice", grant: "app.grant" }]);
      expect(() => sqlOf({}, [...BLOCKS, "tags"])).toThrow(
        "needs subjects.invoice.team",
      );

      contribute([
        { subject: "patient", grant: "app.a" },
        { subject: "patient", grant: "app.b" },
      ]);
      expect(() => sqlOf({}, [...BLOCKS, "tags"])).toThrow(
        `Two blocks contribute "patient" to access-requests`,
      );
    });
  });
});
