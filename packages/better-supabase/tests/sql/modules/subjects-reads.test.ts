import { describe, expect, it } from "vitest";

import type { SubjectsConfig } from "../../../src/config/index.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import {
  auditedSubjects,
  registeredSubjects,
} from "../../../src/sql/subject-registry.ts";

const SUBJECTS: SubjectsConfig = {
  patient: {
    table: "public.patients",
    title: "name",
    permissions: { read: "patients.read" },
    team: { actions: ["read"] },
    auditReads: true,
    deletedAt: "deleted_at",
  },
  invoice: { table: "public.invoices", permissions: { read: "invoices.read" } },
};

const render = (
  blocks: readonly string[],
  modules: Record<string, unknown> = {},
  subjects: SubjectsConfig = SUBJECTS,
): ReturnType<typeof renderBlocks> =>
  // SAFETY: each module takes `on` and its options as plain config here.
  renderBlocks(blocks, { subjects, modules: modules as never });

const sqlOf = (
  files: ReturnType<typeof renderBlocks>,
  module = "subjects",
): string =>
  files
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const READ_CALL = `perform "better_supabase"."record_subject_read"(`;

describe("read logging", () => {
  it("writes record_subject_read and subject_access_log for opted-in types", () => {
    const sql = sqlOf(render(["audit", "subjects"]));

    expect(sql).toContain(
      `create or replace function "better_supabase"."record_subject_read"(subject_type text, subject_id text, purpose text default null, block_name text default null, function_name text default null)`,
    );
    expect(sql).toContain(
      `create or replace function "better_supabase"."subject_access_log"(subject_type text, subject_id text, since timestamptz default null, max_rows integer default 100)`,
    );
    expect(sql).toContain(
      `not (record_subject_read.subject_type = any ('{patient}'::text[]))`,
    );
    expect(sql).toContain(`and s."deleted_at" is null`);
    expect(sql).toContain("event_type => 'subject.accessed'");
    expect(sql).toContain("category => 'read'");
    expect(sql).toContain("make_interval(secs => 60)");
    expect(sql).toContain(`'record_summary');`);
    expect(sql).toContain("hint = 'SUBJECT_READ_FORBIDDEN'");
    expect(sql).toContain("'audit.read'");
    expect(sql).toContain(`m."role" = 'lead'`);
    expect(sql).not.toContain("portal_parties");
  });

  it("logs nothing without an opted-in type", () => {
    const files = render(
      ["audit", "subjects", "comments", "timeline"],
      {},
      { invoice: SUBJECTS["invoice"]! },
    );

    expect(sqlOf(files)).not.toContain(
      `function "better_supabase"."record_subject_read"`,
    );
    expect(sqlOf(files, "comments")).not.toContain("record_subject_read");
    expect(sqlOf(files, "timeline")).not.toContain("record_subject_read");
  });

  it("drops the collapse window at 0 seconds", () => {
    const sql = sqlOf(
      render(["audit", "subjects"], {
        subjects: { options: { reads: { collapseSeconds: 0 } } },
      }),
    );

    expect(sql).toContain("record_subject_read");
    expect(sql).not.toContain("pg_advisory_xact_lock");
    expect(sql).not.toContain("make_interval");
  });

  it("collapses over the configured window", () => {
    const sql = sqlOf(
      render(["audit", "subjects"], {
        subjects: { options: { reads: { collapseSeconds: 300 } } },
      }),
    );

    expect(sql).toContain("make_interval(secs => 300)");
  });

  it.each([-1, 1.5, 86_401, "60"])(
    "rejects collapseSeconds %s",
    (collapseSeconds) => {
      expect(() =>
        render(["audit", "subjects"], {
          subjects: { options: { reads: { collapseSeconds } } },
        }),
      ).toThrow(/collapseSeconds/u);
    },
  );

  it("keeps the default window when reads names no collapseSeconds", () => {
    const sql = sqlOf(
      render(["audit", "subjects"], { subjects: { options: { reads: {} } } }),
    );

    expect(sql).toContain("make_interval(secs => 60)");
  });

  it("rejects reads that isn't an object", () => {
    expect(() =>
      render(["audit", "subjects"], { subjects: { options: { reads: 5 } } }),
    ).toThrow(/collapseSeconds/u);
  });

  it("skips the deleted check for a type without deletedAt", () => {
    const sql = sqlOf(
      render(
        ["audit", "subjects"],
        {},
        {
          patient: {
            table: "public.patients",
            title: "name",
            team: { actions: ["read"] },
            auditReads: true,
          },
        },
      ),
    );

    expect(sql).toContain("record_subject_read");
    expect(sql).not.toContain("deleted_at");
  });

  it("leaves representatives out with relations but no guests", () => {
    const sql = sqlOf(render(["audit", "relations", "subjects"]));

    expect(sql).toContain("subject_access_log");
    expect(sql).not.toContain(`'represents'`);
  });

  it("needs the audit block", () => {
    expect(() => render(["subjects"])).toThrow(/audit/u);
  });

  it("lets guests and act representatives ask with relations and guests installed", () => {
    const sql = sqlOf(render(["audit", "relations", "guests", "subjects"]));

    expect(sql).toContain("portal_parties()");
    expect(sql).toContain(`'represents'`);
    expect(sql).toContain(`->> 'authority' = 'act'`);
  });

  it("calls the read log from the blocks' read functions", () => {
    const files = render([
      "audit",
      "subjects",
      "comments",
      "timeline",
      "state-machine",
      "custom-fields",
    ]);

    expect(sqlOf(files, "comments")).toContain(
      `${READ_CALL}list_comments.subject_type, list_comments.subject_id, null, 'comments', 'list_comments');`,
    );
    expect(sqlOf(files, "timeline")).toContain(
      `${READ_CALL}list_activity.subject_type, list_activity.subject_id, null, 'timeline', 'list_activity');`,
    );
    expect(sqlOf(files, "custom-fields")).toContain(
      `${READ_CALL}read_field_values.subject_type, read_field_values.subject_id, null, 'custom-fields', 'read_field_values');`,
    );
    expect(sqlOf(files, "comments")).toMatch(
      /"list_comments"\([^)]*\)\s+returns jsonb\s+language plpgsql\s+volatile/u,
    );
  });

  it("keeps the read functions stable without read logging", () => {
    const files = render(
      ["audit", "subjects", "comments"],
      {},
      { invoice: SUBJECTS["invoice"]! },
    );

    expect(sqlOf(files, "comments")).toMatch(
      /"list_comments"\([^)]*\)\s+returns jsonb\s+language plpgsql\s+stable/u,
    );
  });
});

describe("auditReads in the registry", () => {
  it("lists the types that log reads", () => {
    const subjects = registeredSubjects(SUBJECTS);

    expect(auditedSubjects(subjects).map((each) => each.type)).toEqual([
      "patient",
    ]);
  });

  it("rejects a value other than true or false", () => {
    expect(() =>
      registeredSubjects({
        // SAFETY: the check under test rejects the wrong type.
        patient: { table: "public.patients", auditReads: "yes" as never },
      }),
    ).toThrow("subjects.patient.auditReads must be true or false");
  });

  it("needs a tenant column", () => {
    expect(() =>
      registeredSubjects({
        patient: { table: "public.patients", tenant: false, auditReads: true },
      }),
    ).toThrow(/auditReads needs a tenant column/u);
  });
});
