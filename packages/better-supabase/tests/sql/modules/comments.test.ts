import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const sqlOf = (
  names: readonly string[],
  options?: Readonly<Record<string, unknown>>,
): string =>
  renderModules(names, { modules: options ? { comments: { options } } : {} })
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

  it("takes create from the subject registry and ignores keys it has no action for", () => {
    const sql = renderModules(["comments"], {
      subjects: {
        deal: {
          table: "deals",
          permissions: {
            read: "deals.read",
            write: "deals.write",
            create: "deals.comment",
          },
        },
      },
    })
      .filter((file) => file.module === "comments")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `case "subject_type" when 'deal' then 'deals.comment' else 'comments.create' end`,
    );
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

  it("checks a subject record's provider scope next to the tenant", () => {
    const withProvider = (options: Readonly<Record<string, unknown>>) =>
      renderModules(["comments"], {
        modules: { access: { model: "provider" }, comments: { options } },
        accessProvider: moduleProvider,
      })
        .filter((file) => file.module === "comments")
        .map((file) => file.contents)
        .join("\n");

    const sql = withProvider({
      subjects: {
        project: { table: "projects", scope: "project" },
        note: { table: "notes" },
      },
    });

    expect(sql).toContain(
      `("subject_type" = 'project' and ("organization_id" in (select better_supabase.tenant_ids_with('comments.read')) or "subject_id" in (select t.id::text from authz.ids_project('comments.read') as t(id))))`,
    );
    expect(sql).toContain(
      `(not coalesce("subject_type" in ('project'), false) and "organization_id" in (select better_supabase.tenant_ids_with('comments.read')))`,
    );
    expect(sql).toContain(
      `or "subject_id" in (select t.id::text from authz.ids_project('comments.create') as t(id))`,
    );
    expect(() =>
      withProvider({
        subjects: { project: { table: "projects", scope: "team" } },
      }),
    ).toThrow(/"team" is not a scope stub declares below its tenant scope/);
    expect(() =>
      withProvider({
        subjects: { project: { table: "projects", scope: "organization" } },
      }),
    ).toThrow(/is not a scope stub declares/);
    expect(() =>
      sqlOf(["comments"], {
        subjects: { project: { table: "projects", scope: "project" } },
      }),
    ).toThrow(/needs blocks.access.model "provider"/);
  });

  it("applies an enforced readableBy to the read policy", () => {
    const enforced = sqlOf(["comments"], {
      subjects: {
        task: {
          table: "tasks",
          readableBy: { sql: "{row}.owner_id = {user}", enforce: true },
        },
        note: { table: "notes", readableBy: "{row}.public" },
      },
    });

    expect(enforced).toContain(
      `and case "subject_type" when 'task' then exists (select 1 from "public"."tasks" s where s."id"::text = "better_supabase"."comments"."subject_id"::text and (s.owner_id = (select auth.uid()))) else true end);`,
    );
    expect(enforced).not.toContain("s.public)) else true");
    expect(() =>
      sqlOf(["comments"], {
        subjects: {
          task: { table: "t", readableBy: { sql: "{row}.x", strict: true } },
        },
      }),
    ).toThrow(/readableBy.strict is not an option/);
    expect(() =>
      sqlOf(["comments"], {
        subjects: { task: { table: "t", readableBy: { enforce: true } } },
      }),
    ).toThrow(/readableBy must be SQL on the subject row/);
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
    expect(() =>
      sqlOf(["comments"], { subjects: { "time-off": { table: "t" } } }),
    ).toThrow(/"time-off" must be lowercase letters, digits and underscores/);
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

  it("makes the author and new mentions follow the subject with notifications", () => {
    const sql = sqlOf(["organizations", "notifications", "comments"]);
    expect(sql).toContain(
      `insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
  select distinct new."organization_id", f.x, new."subject_type", new."subject_id", 'participating'
  from unnest(case when tg_op = 'INSERT' then array[new."author_id"] else '{}'::uuid[] end || v_new) f(x)
  where f.x is not null
  on conflict do nothing;`,
    );

    const quiet = sqlOf(["organizations", "notifications", "comments"], {
      notify: false,
      follow: false,
    });

    expect(quiet).not.toContain("notification_subscriptions");
    expect(sqlOf(["comments"])).not.toContain("notification_subscriptions");
  });

  describe("activity with the subject registry", () => {
    const registry = {
      quote: { table: "sales.quotes", permissions: { read: "quotes.read" } },
      note: { table: "notes" },
    };

    const render = (
      names: readonly string[],
      audit: Readonly<Record<string, unknown>> = {},
    ): string =>
      renderModules(names, {
        subjects: registry,
        modules: { audit: { options: audit } },
      })
        .filter((file) => file.module === "comments")
        .map((file) => file.contents)
        .join("\n");

    it("keeps the tenant check alone without the subjects module", () => {
      const sql = render(["comments"]);
      expect(sql).not.toContain('"activity_subject_readable"("subject_type"');
      expect(sql).toContain(
        `drop function if exists "better_supabase"."activity_subject_readable"(text, text);`,
      );
      expect(sql).toContain(`'source', 'event'`);
      expect(sql).not.toContain("audit_events");
    });

    it("checks can_subject per row and once for a subject's timeline", () => {
      const sql = render(["comments", "subjects"]);
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
      expect(render(["audit", "comments", "subjects"])).not.toContain(
        "audit_events",
      );

      const sql = render(["access", "audit", "comments", "subjects"], {
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
      const sql = render(["comments", "subjects"]);
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
      const sql = render(["access", "comments", "subjects", "workflows"]);
      expect(sql).toContain(`from "better_supabase"."workflow_runs" r`);
      expect(sql).toContain(`'type', 'run.' || r."status"`);
      expect(sql).toContain(
        `(list_activity.sources is null or 'run' = any (list_activity.sources))`,
      );
      expect(sql).toContain(`'source', 'run'`);
    });

    it("reads a registered subject's deliveries through a definer helper", () => {
      const sql = render(["access", "comments", "notifications", "subjects"]);
      expect(sql).toContain(
        `create or replace function "better_supabase"."activity_subject_deliveries"(tenant uuid, subject_type text, subject_id text, before timestamptz, max_rows integer)`,
      );
      expect(sql).toMatch(
        /activity_subject_deliveries"\(tenant uuid[\s\S]*?security definer/,
      );
      expect(sql).toContain("'activity.read'");
      expect(sql).toContain("'notifications.send'");
      expect(sql).toContain(
        `(list_activity.sources is null or 'delivery' = any (list_activity.sources))`,
      );
      expect(sql).toContain(`'source', 'delivery'`);
    });
  });
});
