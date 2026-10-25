import { describe, expect, it } from "vitest";

import type { SubjectsConfig } from "../../../src/config/index.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const SUBJECTS: SubjectsConfig = {
  task: {
    table: "public.tasks",
    idType: "bigint",
    title: "title",
    url: "/projects/{project_id}/tasks/{id}",
    permissions: { read: "tasks.read", write: "tasks.update" },
  },
  note: { table: "public.notes", tenant: false },
};

const sqlOf = (
  modules: readonly string[],
  layout: Parameters<typeof renderBlocks>[1] = {},
): string =>
  renderBlocks(modules, { subjects: SUBJECTS, ...layout })
    .map((file) => file.contents)
    .join("\n");

describe("subjects module", () => {
  it("writes subject_title, subject_url and can_subject from the registry", () => {
    const sql = sqlOf(["subjects"]);
    expect(sql).toContain(
      `return (select s."title"::text from "public"."tasks" s where s."id" = (subject_title.subject_id)::bigint);`,
    );
    expect(sql).toContain(
      `'/projects/' || s."project_id"::text || '/tasks/' || s."id"::text`,
    );
    expect(sql).toContain(
      `when 'write' then coalesce(better_supabase.can('tenant', s."organization_id", 'tasks.update'), false)`,
    );
    expect(sql).toContain(`select '{task,note}'::text[]`);
    expect(sql).toContain("security invoker");
  });

  it("writes subject_titles with one query per type, cast to the id type", () => {
    const sql = sqlOf(["subjects"]);
    expect(sql).toContain(
      `create or replace function "better_supabase"."subject_titles"(refs jsonb)`,
    );
    expect(sql).toContain(
      `where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'task')::bigint[])), '[]'::jsonb);`,
    );
    expect(sql).toContain(
      `'type', 'note', 'id', s."id"::text,\n      'title', null::text, 'url', null::text))`,
    );
    expect(sql).toContain("hint = 'SUBJECT_REFS_TOO_MANY'");
    expect(sql).toContain("hint = 'SUBJECT_ID_INVALID'");
    expect(sql).toContain(
      `grant execute on function "better_supabase"."subject_titles"(jsonb) to authenticated, service_role;`,
    );
  });

  it("skips soft-deleted rows in subject_titles", () => {
    const sql = renderBlocks(["subjects"], {
      subjects: {
        doc: { table: "docs", title: "name", deletedAt: "trashed_at" },
      },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toMatch(
      /r ->> 'type' = 'doc'\)\) and s\."trashed_at" is null\), '\[\]'::jsonb\);/,
    );
  });

  it("writes can_subject_for through can_user, false for an action without a key", () => {
    const sql = sqlOf(["subjects"]);
    expect(sql).toContain(
      `when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'tasks.read'), false)`,
    );
    expect(sql).toMatch(
      /when 'note' then\s+return exists \(\s+select 1 from "public"."notes" s\s+where s."id"::text = can_subject_for.subject_id\s+and false/,
    );
    expect(sql).toContain(
      `grant execute on function "better_supabase"."can_subject_for"(uuid, text, text, text) to service_role;`,
    );
  });

  it("treats soft-deleted rows as gone", () => {
    const sql = renderBlocks(["subjects"], {
      subjects: {
        doc: { table: "docs", title: "name", deletedAt: "trashed_at" },
      },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `where s."id"::text = subject_title.subject_id and s."trashed_at" is null);`,
    );
    expect(sql).toContain(
      `where s."id"::text = can_subject.subject_id and s."trashed_at" is null`,
    );
  });

  it("rejects a url placeholder that is not a column", () => {
    expect(() =>
      renderBlocks(["subjects"], {
        subjects: { task: { table: "tasks", url: "/tasks/{id;drop}" } },
      }),
    ).toThrow(/subjects\.task\.url/);
  });

  it("rejects permissions on a subject with neither a tenant nor a scope", () => {
    expect(() =>
      renderBlocks(["subjects"], {
        subjects: {
          note: {
            table: "notes",
            tenant: false,
            permissions: { read: "notes.read" },
          },
        },
      }),
    ).toThrow(/need a tenant column or a scope/);
  });
});

describe("subject actions beyond tenant keys", () => {
  const ROWS: SubjectsConfig = {
    file_node: {
      table: "public.file_nodes",
      idType: "uuid",
      permissions: {
        read: { key: "file.read", rows: "file_node" },
        share: { rows: "file_node", key: "file.update" },
      },
    },
    thread: {
      table: "public.threads",
      permissions: { share: { owner: "owner_user_id" } },
    },
  };

  const provider = {
    ...moduleProvider,
    functions: {
      ...moduleProvider.functions,
      rowsWith: "authz.rows_{resource}({permission}, {ids})",
      rowsWithFor: "authz.rows_{resource}_for({user}, {permission}, {ids})",
    },
  };

  const render = (layout: Parameters<typeof renderBlocks>[1]): string =>
    renderBlocks(["subjects"], {
      subjects: ROWS,
      modules: { permissions: { model: "provider" } },
      ...layout,
    })
      .map((file) => file.contents)
      .join("\n");

  it("grants an action through the provider's row set or an owner column", () => {
    const sql = render({ accessProvider: provider });

    expect(sql).toContain(
      `s."id"::text in (select r.id::text from authz.rows_file_node('file.update', array[s."id"::text]) as r(id))`,
    );
    expect(sql).toContain(`when 'share' then s."owner_user_id" = auth.uid()`);
    expect(sql).toContain(
      `authz.rows_file_node_for(can_subject_for.member, 'file.read', array[s."id"::text])`,
    );
    expect(sql).toContain(
      `when 'share' then s."owner_user_id" = can_subject_for.member`,
    );
  });

  it("answers row grants for the caller only without rowsWithFor", () => {
    const { rowsWithFor: _unused, ...callerOnly } = provider.functions;

    const sql = render({
      accessProvider: { ...provider, functions: callerOnly },
    });

    expect(sql).not.toContain("rows_file_node_for");
    expect(sql).toMatch(
      /can_subject_for\.member, 'tenant', s\."organization_id", 'file\.update'\), false\) or false\)/u,
    );
  });

  it("refuses rows without a provider rowsWith template", () => {
    expect(() => render({ accessProvider: moduleProvider })).toThrow(
      /records\.file_node\.permissions\.read\.rows needs/u,
    );
  });

  it("checks the entry's shape", () => {
    const bad = (permission: unknown) => () =>
      renderBlocks(["subjects"], {
        subjects: {
          // SAFETY: the test passes shapes the type refuses on purpose.
          doc: { table: "docs", permissions: { share: permission } } as never,
        },
      });

    expect(bad({ rows: "doc" })).toThrow(/rows needs the key/u);
    expect(bad({ rows: "Doc-x", key: "a" })).toThrow(/SQL name of a resource/u);
    expect(bad({ owner: "x;y" })).toThrow(/owner must be a column name/u);
    expect(bad({})).toThrow(/needs a key or an owner column/u);
    expect(bad({ key: "a", other: 1 })).toThrow(/other is not an option/u);
  });

  it("lets an owner-only action stand on a subject without a tenant", () => {
    expect(() =>
      renderBlocks(["subjects"], {
        subjects: {
          note: {
            table: "notes",
            tenant: false,
            permissions: { write: { owner: "user_id" } },
          },
        },
      }),
    ).not.toThrow();
  });
});

describe("subjectsOption with the registry", () => {
  it("falls back to every registered subject with a tenant", () => {
    const sql = sqlOf(["tags"]);
    expect(sql).toContain(
      `when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (tag.subject_id)::bigint`,
    );
    expect(sql).toContain(`'tasks.read'`);
    expect(sql).not.toContain(`"public"."notes"`);
  });

  it("takes a list of registered types", () => {
    const sql = sqlOf(["attachments"], {
      modules: { attachments: { on: ["note"] } },
    });

    expect(sql).toContain(`"public"."notes"`);
    expect(sql).not.toContain(`"public"."tasks"`);
  });

  it("merges an object entry onto the registered one", () => {
    const sql = sqlOf(["tags"], {
      modules: { tags: { on: { task: { permission: "tasks.tag" } } } },
    });

    expect(sql).toContain(`'tasks.tag'`);
    expect(sql).toContain(`(tag.subject_id)::bigint`);
  });

  it("rejects a listed type the registry lacks", () => {
    expect(() =>
      renderBlocks(["tags"], {
        subjects: SUBJECTS,
        modules: { tags: { on: ["deal"] } },
      }),
    ).toThrow(/"deal" is not a subject type in config\.records/);
  });

  it("leaves webhooks-in without subjects unless it lists them", () => {
    const sql = sqlOf(["webhooks-in"]);
    expect(sql).not.toContain(`"public"."tasks"`);
  });

  it("authorizes a record's presence topic for its readers", () => {
    const sql = sqlOf(["subjects"]);
    expect(sql).toContain(
      `"better_supabase"."subject_presence_allowed"(topic text)`,
    );
    expect(sql).toContain(
      "regexp_match(subject_presence_allowed.topic, '^presence:([a-z][a-z0-9_-]{0,62}):([^:]{1,200})$')",
    );
    expect(sql).toContain(
      `coalesce("better_supabase"."can_subject"(v_parts[1], v_parts[2], 'read'), false)`,
    );
    expect(sql).toContain("realtime.messages.extension = 'presence'");
    expect(sql).toContain("bsb_subject_presence_receive");
    expect(sql).toContain("bsb_subject_presence_send");
  });
});
