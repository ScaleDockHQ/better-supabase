import { describe, expect, it } from "vitest";

import { customContracts, renderModules } from "../../../src/sql/render.ts";

const sqlOf = (
  options: Record<string, unknown> = {},
  extra: readonly string[] = [],
): string =>
  renderModules(["engagements", ...extra], {
    subjects: {
      deal: { table: "public.deals" },
      note: { table: "public.notes", tenant: false },
    },
    modules: { engagements: { options } },
  })
    .filter((file) => file.module === "engagements")
    .map((file) => file.contents)
    .join("\n");

describe("engagements module", () => {
  it("checks every subject's tenant and readability", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      `when 'deal' then exists (select 1 from "public"."deals" s where s."id"::text = (v_item ->> 'id') and s."organization_id"::text = v_tenant::text)`,
    );
    expect(sql).not.toContain(`when 'note' then`);
    expect(sql).toContain("'{call,email,meeting,note,task}'::text[]");
    expect(sql).not.toContain("engagement.assigned");
  });

  it("notifies an assigned owner with notifications installed", () => {
    expect(sqlOf({}, ["notifications"])).toContain(
      "'type', 'engagement.assigned'",
    );
  });

  it("takes configured types and rejects bad ones", () => {
    expect(sqlOf({ types: ["call", "visit"] })).toContain(
      "'{call,visit}'::text[]",
    );
    expect(() => sqlOf({ types: ["Visit"] })).toThrow(/lowercase names/);
  });
});

describe("engagements module, layouts", () => {
  it("renders nothing in custom mode and refuses every subject without a registry", () => {
    expect(
      renderModules(["engagements"], {
        modules: { engagements: { mode: "custom" } },
      })
        .filter((file) => file.module === "engagements")
        .map((file) => file.contents)
        .join(""),
    ).not.toContain("log_engagement");

    const sql = renderModules(["engagements"], {})
      .filter((file) => file.module === "engagements")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("if not false then");
  });
});

describe("engagements module, recordings", () => {
  it("adds nothing by default", () => {
    const sql = sqlOf();
    expect(sql).not.toContain("engagement_recordings");
    expect(sql).not.toContain("save_engagement_notes");
  });

  it("stores recordings on ai-files with transcripts and notes", () => {
    const sql = sqlOf({ recordings: true });
    expect(sql).toContain(
      'create table if not exists "better_supabase"."engagement_recordings"',
    );
    expect(sql).toContain('references "better_supabase"."ai_files"');
    expect(sql).toContain(
      'create table if not exists "better_supabase"."engagement_transcript_segments"',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."engagement_notes"',
    );
    expect(sql).toContain(
      'function "better_supabase"."attach_engagement_recording"',
    );
    expect(sql).not.toContain("engagements.transcribe:");
  });

  it("emits recording events with outbox installed", () => {
    const sql = sqlOf({ recordings: true }, ["outbox"]);
    expect(sql).toContain("'engagement.recorded'");
    expect(sql).toContain("'engagement.transcribed'");
    expect(sql).toContain("'engagement.summarized'");
  });

  it("queues a transcription with jobs installed", () => {
    expect(sqlOf({ recordings: true }, ["jobs"])).toContain(
      "'engagements.transcribe:' || v_recording::text",
    );
  });

  it("needs a managed ai-files block", () => {
    expect(() =>
      renderModules(["engagements"], {
        modules: {
          engagements: { options: { recordings: true } },
          "ai-files": { mode: "custom" },
        },
      }),
    ).toThrow(/ai-files/);
  });

  it("lists the recording functions in the contract only when on", () => {
    const names = (options: Record<string, unknown>) =>
      customContracts(["engagements"], {
        modules: { engagements: { mode: "custom", options } },
      })
        .find((contract) => contract.module === "engagements")
        ?.functions.map((fn) => fn.name);

    expect(names({})).not.toContain("save_engagement_notes");
    expect(names({ recordings: true })).toEqual(
      expect.arrayContaining([
        "attach_engagement_recording",
        "save_engagement_transcript",
        "save_engagement_notes",
      ]),
    );
  });
});
