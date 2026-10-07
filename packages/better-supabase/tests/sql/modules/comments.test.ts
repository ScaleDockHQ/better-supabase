import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/registry.ts";

const sqlOf = (
  names: readonly string[],
  options?: Readonly<Record<string, unknown>>,
): string =>
  renderModules(names, {
    modules: options ? { comments: { options } } : {},
  })
    .filter((file) => file.contents.includes("activity_entries"))
    .map((file) => file.contents)
    .join("\n");

describe("comments module", () => {
  it("accepts any subject without options.subjects and skips notifications without the module", () => {
    const sql = sqlOf(["comments"]);
    expect(sql).toMatch(/create table if not exists \S+comments/);
    expect(sql).toMatch(/create table if not exists \S+activity_entries/);
    expect(sql).toContain("'comments.moderate'");
    expect(sql).toContain("'activity.read'");
    expect(sql).not.toContain('"notify"(');
    expect(sql).not.toContain("emit_event");
  });

  it("checks each configured subject's table, tenant and permission", () => {
    const sql = sqlOf(
      ["organizations", "outbox", "notifications", "comments"],
      {
        subjects: {
          project: { table: "app.projects", permission: "projects.read" },
          ticket: { table: "tickets", id: "ticket_id", tenant: "team_id" },
        },
        maxBodyLength: 2000,
      },
    );
    expect(sql).toContain(
      `when 'project' then exists (select 1 from "app"."projects" s where s."id"::text = subject_id and s."organization_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'projects.read'), false)`,
    );
    expect(sql).toContain(
      `when 'ticket' then exists (select 1 from "public"."tickets" s where s."ticket_id"::text = subject_id and s."team_id" = tenant)`,
    );
    expect(sql).toContain("<= 2000");
    expect(sql).toContain('"better_supabase"."notify"(jsonb_build_object(');
    expect(sql).toMatch(/emit_event\('comment\.created'/);
  });

  it("checks a subject type's own permission per action", () => {
    const sql = sqlOf(["comments"], {
      subjects: {
        deal: { table: "deals", permissions: { create: "deals.comment" } },
        project: { table: "projects" },
      },
    });
    expect(sql).toContain(
      `case "subject_type" when 'deal' then 'deals.comment' else 'comments.create' end`,
    );
    expect(sql).toContain(
      `coalesce(better_supabase.can('tenant', "organization_id", 'comments.read'), false) and`,
    );
    expect(() =>
      sqlOf(["comments"], {
        subjects: { deal: { table: "deals", permissions: { delete: "x" } } },
      }),
    ).toThrow(/use read, create and moderate/);
    expect(() =>
      sqlOf(["comments"], {
        subjects: { deal: { table: "deals", permissions: "x" } },
      }),
    ).toThrow(/must be \{ read\?/);
  });

  it.each([
    [{ subjects: [] }, /pass an object/],
    [{ subjects: { "Bad-Type": { table: "x" } } }, /lowercase letters/],
    [{ subjects: { project: {} } }, /needs a table/],
    [{ subjects: { project: { table: "x", id: 1 } } }, /id must be a string/],
    [{ maxBodyLength: 0 }, /whole number above zero/],
  ])("rejects %j", (options, message) => {
    expect(() => sqlOf(["comments"], options)).toThrow(message);
  });

  it("cascades subject deletes and checks the document with a JSON Schema", () => {
    const sql = sqlOf(["jsonb-schemas", "comments"], {
      subjects: {
        task: { table: "app.tasks", cascade: true },
        note: { table: "notes" },
      },
      documentSchema: { type: "object", required: ["type"] },
    });
    expect(sql).toContain('create trigger "bs_comments_task_cascade"');
    expect(sql).toContain('after delete on "app"."tasks"');
    expect(sql).not.toContain("bs_comments_note_cascade");
    expect(sql).toContain("bs_json_document");
    expect(() =>
      sqlOf(["comments"], { documentSchema: { type: "object" } }),
    ).toThrow(/add the jsonb-schemas module/);
    expect(() =>
      sqlOf(["comments"], { subjects: { task: { table: "t", bucket: "x" } } }),
    ).toThrow(/subjects.task.bucket is not an option/);
    expect(() =>
      sqlOf(["comments"], {
        subjects: { task: { table: "t", cascade: "yes" } },
      }),
    ).toThrow(/cascade must be true or false/);
  });
});
