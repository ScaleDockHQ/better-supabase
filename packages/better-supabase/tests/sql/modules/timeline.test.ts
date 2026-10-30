import { describe, expect, it } from "vitest";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";

describe("activity module", () => {
  const registry = {
    quote: { table: "sales.quotes", permissions: { read: "quotes.read" } },
    note: { table: "notes" },
  };

  const render = (
    names: readonly string[],
    audit: Readonly<Record<string, unknown>> = {},
  ): string =>
    renderBlocks(names, {
      subjects: registry,
      modules: { audit: { options: audit } },
    })
      .filter((file) => file.module === "timeline")
      .map((file) => file.contents)
      .join("\n");

  it("keeps the tenant check alone without the subjects module", () => {
    const sql = render(["timeline"]);
    expect(sql).not.toContain('"activity_subject_readable"("subject_type"');
    expect(sql).toContain(
      `drop function if exists "better_supabase"."activity_subject_readable"(text, text);`,
    );
    expect(sql).toContain(`'source', 'event'`);
    expect(sql).not.toContain("audit_events");
  });

  it("checks can_subject per row and once for a subject's timeline", () => {
    const sql = render(["timeline", "subjects"]);
    expect(sql).toContain(
      `return coalesce("better_supabase"."can_subject"(subject_type, subject_id, 'read'), false);`,
    );
    expect(sql).toContain(
      `or not ("subject_type" = any ('{quote,note}'::text[]))
      or "better_supabase"."activity_subject_readable"("subject_type", "subject_id")));`,
    );
    expect(sql).toContain(
      `if list_activity.subject_id is not null and list_activity.subject_type = any ('{quote,note}'::text[])
    and not "better_supabase"."activity_subject_readable"(list_activity.subject_type, list_activity.subject_id) then
    return '[]'::jsonb;`,
    );
    expect(sql).not.toContain("audit_events");
  });

  it("joins the subject's audit entries when the audit read policy is on", () => {
    expect(render(["audit", "timeline", "subjects"])).not.toContain(
      "audit_events",
    );

    const sql = render(["permissions", "audit", "timeline", "subjects"], {
      readPolicy: true,
    });

    expect(sql).toContain(
      `      when 'quote' then 'sales.quotes'\n      when 'note' then 'public.notes'`,
    );
    expect(sql).toContain(`from "better_supabase"."audit_events" l`);
    expect(sql).toContain(`and l."table_name" = v_table`);
    expect(sql).toContain(`and l."record_id" = list_activity.subject_id`);
    expect(sql).toContain(
      `'type', coalesce(l."event_type", 'audit.' || l."op")`,
    );
    expect(sql).toContain(`'source', 'audit'`);
  });

  it("filters by sources and leaves out deliveries and runs without their modules", () => {
    const sql = render(["timeline", "subjects"]);
    expect(sql).toContain("sources text[] default null");
    expect(sql).toContain(
      `(list_activity.sources is null or 'event' = any (list_activity.sources))`,
    );
    expect(sql).not.toContain("workflow_runs");
    expect(sql).toContain(
      `drop function if exists "better_supabase"."activity_subject_deliveries"(uuid, text, text, timestamptz, integer);`,
    );
  });

  it("unions a registered subject's workflow runs, read as the caller", () => {
    const sql = render(["permissions", "timeline", "subjects", "workflows"]);
    expect(sql).toContain(`from "better_supabase"."workflow_runs" r`);
    expect(sql).toContain(`'type', 'run.' || r."status"`);
    expect(sql).toContain(
      `(list_activity.sources is null or 'run' = any (list_activity.sources))`,
    );
    expect(sql).toContain(`'source', 'run'`);
  });

  it("reads a registered subject's deliveries through a definer helper", () => {
    const sql = render([
      "permissions",
      "timeline",
      "notifications",
      "subjects",
    ]);

    expect(sql).toContain(
      `create or replace function "better_supabase"."activity_subject_deliveries"(tenant uuid, subject_type text, subject_id text, before timestamptz, max_rows integer)`,
    );
    expect(sql).toMatch(
      /activity_subject_deliveries"\(tenant uuid[\s\S]*?security definer/,
    );
    expect(sql).toContain("'timeline.read'");
    expect(sql).toContain("'notifications.send'");
    expect(sql).toContain(
      `(list_activity.sources is null or 'delivery' = any (list_activity.sources))`,
    );
    expect(sql).toContain(`'source', 'delivery'`);
  });

  it("renders nothing for a custom implementation", () => {
    expect(
      moduleBody("timeline", { modules: { timeline: { mode: "custom" } } }),
    ).toBeFalsy();
  });
});
