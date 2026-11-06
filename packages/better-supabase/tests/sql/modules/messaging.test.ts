import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("messaging", { modules })!;

describe("messaging module", () => {
  it("checks its options", () => {
    for (const [options, message] of [
      [{ topic: "Bad Topic" }, /options.topic/],
      [{ threadDepth: 2 }, /options.threadDepth/],
      [{ maxBodyLength: 0 }, /options.maxBodyLength/],
      [{ maxBodyLength: 1.5 }, /options.maxBodyLength/],
      [{ editWindow: -1 }, /options.editWindow/],
      [{ editWindow: 0.5 }, /options.editWindow/],
      [{ scheduleQueue: "Bad Queue" }, /options.scheduleQueue/],
    ] as const) {
      expect(() => body({ messaging: { options } })).toThrow(message);
    }
  });

  it("flattens replies into the root unless threads nest", () => {
    const flat = body();

    const nested = body({
      messaging: { options: { threadDepth: "unlimited" } },
    });

    expect(flat).not.toBe(nested);
    expect(body({ messaging: { options: { threadDepth: 1 } } })).toBe(flat);
  });

  it("names the topic, the body limit and the edit window", () => {
    const sql = body({
      messaging: {
        options: { topic: "chat", maxBodyLength: 500, editWindow: 600 },
      },
    });

    expect(sql).toContain("'chat:'");
    expect(sql).toContain("500");
    expect(sql).toContain("600");
  });

  it("prunes a commented record type with row grants to the record table's visible set", () => {
    const provider = {
      ...moduleProvider,
      functions: {
        ...moduleProvider.functions,
        rowsWith: "authz.rows_{resource}({permission}, {ids})",
        rowsWithFor: "authz.rows_{resource}_for({user}, {permission}, {ids})",
      },
    };

    const sql = renderBlocks(["messaging"], {
      modules: { permissions: { model: "provider" } },
      subjects: {
        file_node: {
          table: "public.file_nodes",
          idType: "uuid",
          permissions: {
            comment: { key: "fileNode.comment", rows: "file_node" },
            read: { key: "fileNode.read", rows: "file_node" },
          },
        },
        note: {
          table: "public.notes",
          permissions: { comment: "notes.comment" },
        },
      },
      accessProvider: provider,
    })
      .filter((file) => file.module === "messaging")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `coalesce(case "better_supabase"."conversations"."subject_type" when 'file_node' then "better_supabase"."conversations"."subject_id" in (select s."id"::text from "public"."file_nodes" s) when 'note' then true else false end, false)`,
    );
  });

  it("keeps the membership test when no commented record type has row grants", () => {
    const sql = renderBlocks(["messaging"], {
      modules: { permissions: { model: "provider" } },
      subjects: {
        drive_node: {
          table: "public.drive_nodes",
          idType: "uuid",
          permissions: { comment: "driveNode.comment" },
        },
      },
      accessProvider: moduleProvider,
    })
      .filter((file) => file.module === "messaging")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `"better_supabase"."conversations"."subject_type" in ('drive_node')`,
    );
  });

  it("opens a record's conversation to a grant on the record's scope", () => {
    const render = (provider: boolean) =>
      renderBlocks(["messaging"], {
        modules: provider ? { permissions: { model: "provider" } } : {},
        subjects: {
          project: { table: "projects", scope: "project" },
          note: { table: "notes" },
        },
        ...(provider ? { accessProvider: moduleProvider } : {}),
      })
        .filter((file) => file.module === "messaging")
        .map((file) => file.contents)
        .join("\n");

    expect(render(true)).toContain(
      `when 'project' then "better_supabase"."conversations"."subject_id" in (select t.id::text from authz.ids_project('messages.read') as t(id))`,
    );
    expect(render(false)).toContain(
      `when 'project' then coalesce(better_supabase.can('project', "better_supabase"."conversations"."subject_id", 'messages.read'), false)`,
    );
    expect(body()).not.toContain(`"permissions" = 'subject' and`);
  });

  it("mentions on a record notify only members who read it", () => {
    const sql = renderBlocks(["notifications", "messaging"], {
      modules: {},
      subjects: {
        deal: { table: "deals", permissions: { read: "deals.read" } },
        note: { table: "notes" },
      },
    })
      .filter((file) => file.module === "messaging")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `when 'deal' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false)`,
    );
    expect(sql).not.toContain("when 'note' then coalesce");
    expect(
      renderBlocks(["notifications", "messaging"], {
        modules: {},
        subjects: { note: { table: "notes" } },
      })
        .filter((file) => file.module === "messaging")
        .map((file) => file.contents)
        .join("\n"),
    ).not.toContain("can_subject_for");
  });

  it("opens a record's conversation only in the record's tenant", () => {
    const sql = renderBlocks(["messaging"], {
      modules: {},
      subjects: {
        deal: { table: "deals", tenant: "workspace_id" },
        note: { table: "notes", tenant: false },
      },
    })
      .filter((file) => file.module === "messaging")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `when 'deal' then (select s."workspace_id"::text from "public"."deals" s where s."id"::text = (open_conversation.attrs ->> 'subjectId'))`,
    );
    expect(sql).not.toContain(`when 'note' then (select`);
    expect(sql).toContain(
      `<> open_conversation.tenant::text, false) then
        raise exception 'no such record in this organization'`,
    );
  });

  it("labels its notifications and sends none with options.notify false", () => {
    const render = (options: Readonly<Record<string, unknown>> = {}) =>
      renderBlocks(["notifications", "messaging"], {
        modules: { messaging: { options } },
        subjects: { deal: { table: "deals", title: "name" } },
      })
        .filter((file) => file.module === "messaging")
        .map((file) => file.contents)
        .join("\n");

    const sql = render();
    expect(sql).toContain(
      `'subject_label', coalesce(case when v_conv."kind" = 'subject' then "better_supabase"."subject_title"(v_conv."subject_type", v_conv."subject_id") end, v_conv."title"),`,
    );
    expect(sql).toContain(`if v_msg."thread_id" is not null and (exists (`);
    expect(sql).toContain("'message.mentioned'");

    const quiet = render({ notify: false });
    expect(quiet).not.toContain("'message.mentioned'");
    expect(quiet).not.toContain("'message.direct'");
    expect(quiet).not.toContain("'message.replied'");
    expect(quiet).not.toContain("v_claims");
    expect(quiet).toContain(
      `insert into "better_supabase"."notification_subscriptions"`,
    );
    expect(() => body({ messaging: { options: { notify: 1 } } })).toThrow(
      /notify/,
    );
  });

  it("renders nothing for a custom implementation", () => {
    expect(
      moduleBody("messaging", { modules: { messaging: { mode: "custom" } } }),
    ).toBeFalsy();
  });

  it("indexes record mentions on send and lists a record's backlinks", () => {
    const sql = body();
    expect(sql).toContain(
      'create table "better_supabase"."message_record_mentions"',
    );
    expect(sql).toContain(
      `perform "better_supabase"."index_record_mentions"(v_msg."id");`,
    );
    expect(sql).toContain("limit 20");
    expect(sql).toContain(
      `revoke execute on function "better_supabase"."index_record_mentions"(uuid) from public, anon, authenticated;`,
    );
    expect(sql).toContain(
      `"list_record_mentions"(subject_type text, subject_id text`,
    );
  });
});

describe("messaging authors with profiles", () => {
  const authors = (options?: Record<string, unknown>) =>
    renderBlocks(["profiles", "messaging"], {
      modules: options === undefined ? {} : { profiles: { options } },
    })
      .map((file) => file.contents)
      .join("\n");

  it("reads the avatar URL column by default", () => {
    const sql = authors();

    expect(sql).toContain("'avatarUrl', pr.\"avatar_url\"");
    expect(sql).not.toContain("'avatarPath'");
  });

  it("reads the Storage path in path mode", () => {
    const sql = authors({ avatarSource: "path" });

    expect(sql).toContain(
      "'avatarUrl', null::text, 'avatarPath', pr.\"avatar_path\"",
    );
  });

  it("rejects an unknown avatar source", () => {
    expect(() => authors({ avatarSource: "gravatar" })).toThrow(
      /options.avatarSource/,
    );
  });
});
