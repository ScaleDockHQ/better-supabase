import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody, renderModules } from "../../../src/sql/render.ts";
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

  it("opens a record's conversation to a grant on the record's scope", () => {
    const render = (provider: boolean) =>
      renderModules(["messaging"], {
        modules: provider ? { access: { model: "provider" } } : {},
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
    expect(body()).not.toContain(`"access" = 'subject' and`);
  });

  it("mentions on a record notify only members who read it", () => {
    const sql = renderModules(["notifications", "messaging"], {
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
      renderModules(["notifications", "messaging"], {
        modules: {},
        subjects: { note: { table: "notes" } },
      })
        .filter((file) => file.module === "messaging")
        .map((file) => file.contents)
        .join("\n"),
    ).not.toContain("can_subject_for");
  });

  it("renders nothing for a custom implementation", () => {
    expect(
      moduleBody("messaging", { modules: { messaging: { mode: "custom" } } }),
    ).toBeFalsy();
  });

  it("indexes record mentions on send and lists a record's backlinks", () => {
    const sql = body();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."message_record_mentions"',
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
