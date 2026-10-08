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

  it("expands group mentions before the read check with options.mentionGroups", () => {
    const plain = sqlOf(["organizations", "notifications", "comments"]);
    expect(plain).toContain(
      `select x from unnest(new."mentions") x\n    where (tg_op = 'INSERT' or not x = any(old."mentions"))`,
    );
    const sql = sqlOf(["organizations", "notifications", "comments"], {
      mentionGroups: {
        table: "app.team_members",
        group: "team_id",
        member: "user_id",
        tenant: "organization_id",
      },
    });
    expect(sql).toContain(
      `select e.x from (select m.x from unnest(new."mentions") m(x) union select g."user_id" from "app"."team_members" g where g."team_id" = any(new."mentions") and g."organization_id" = new."organization_id") e(x)`,
    );
    expect(sql).toContain(`where e.x is distinct from new."author_id"`);
    expect(sql).toContain(
      `not e.x = any(array(select o.x from (select m.x from unnest(old."mentions") m(x) union select g."user_id" from "app"."team_members" g where g."team_id" = any(old."mentions")`,
    );
    expect(sql).toContain(`better_supabase.can_user(e.x, 'tenant',`);
    expect(
      sqlOf(["organizations", "notifications", "comments"], {
        mentionGroups: { table: "teams", group: "id", member: "user_id" },
      }),
    ).toContain(
      `union select g."user_id" from "public"."teams" g where g."id" = any(new."mentions")) e(x)`,
    );
    expect(() =>
      sqlOf(["comments"], { mentionGroups: { table: "teams" } }),
    ).toThrow("needs table, group and member");
    expect(() => sqlOf(["comments"], { mentionGroups: "teams" })).toThrow(
      "must be { table, group, member, tenant? }",
    );
    expect(() =>
      sqlOf(["comments"], {
        mentionGroups: { table: "t", group: "g", member: "m", kind: "x" },
      }),
    ).toThrow("mentionGroups.kind is not an option");
    expect(() =>
      sqlOf(["comments"], {
        mentionGroups: { table: "t", group: "g", member: 1 },
      }),
    ).toThrow("member must be a non-empty string");
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
      `using ("organization_id" in (select better_supabase.tenant_ids_with('comments.read')) and`,
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

  it("labels mention notifications, filters recipients by the subject and can stay quiet", () => {
    const subjects = {
      task: {
        table: "tasks",
        idType: "uuid",
        permission: "tasks.read",
        permissions: { read: "tasks.comments.read" },
        label: "{row}.title",
        path: "'/tasks/' || {row}.id",
        readableBy: "{row}.owner_id = {user}",
      },
    };
    const sql = sqlOf(["notifications", "comments"], { subjects });
    expect(sql).toContain(
      `'subject_label', case new."subject_type" when 'task' then (select (s.title)::text from "public"."tasks" s where s."id" = (new."subject_id"::text)::uuid limit 1) end`,
    );
    expect(sql).toContain(`then (select ('/tasks/' || s.id)::text`);
    expect(sql).toContain(
      `case new."subject_type" when 'task' then 'tasks.comments.read' else 'comments.read' end`,
    );
    expect(sql).toContain(
      `coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'tasks.read'), false) and exists (select 1 from "public"."tasks" s where s."id" = (new."subject_id"::text)::uuid and (s.owner_id = x))`,
    );
    const quiet = sqlOf(["notifications", "comments"], {
      subjects,
      notify: false,
    });
    expect(quiet).not.toContain('"notify"(');
    expect(quiet).toContain("comments_after_write");
    const plain = sqlOf(["notifications", "comments"]);
    expect(plain).toContain("'subject_label', null::text");
    expect(() =>
      sqlOf(["comments"], {
        subjects: { task: { table: "tasks", label: "title" } },
      }),
    ).toThrow(/subjects\.task\.label must be SQL on the subject row \{row\}/);
  });
});
