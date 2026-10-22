import { describe, expect, it } from "vitest";

import { withBlockSubjects } from "../../../src/config/block-subjects.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (
  modules: readonly string[],
  module: string,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("reactions module", () => {
  it("checks registry subjects and refuses other types", () => {
    const sql = sqlOf(["reactions"], "reactions", {
      subjects: { doc: { table: "public.docs", idType: "uuid" } },
    });

    expect(sql).toContain(
      `when 'doc' then exists (select 1 from "public"."docs" s`,
    );
    expect(sql).toContain("else false");
    expect(sql).not.toContain("'comment'");
    expect(sql).not.toContain("'inbox_message'");
  });

  it("sees messages (and so comments and inbox messages) through their own policies", () => {
    const modules = ["reactions", "messaging", "comments", "inbox"];

    const sql = sqlOf(modules, "reactions", {
      subjects: withBlockSubjects({}, modules, {}),
    });

    expect(sql).toContain(
      `when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."deleted_at" is null)`,
    );
    expect(sql).not.toContain("react_to_message");
    expect(sql).not.toContain(`when 'comment'`);
    expect(sql).not.toContain(`when 'inbox_message'`);
  });

  it("keeps messages when on lists other types", () => {
    const modules = ["reactions", "messaging", "comments"];

    const sql = sqlOf(modules, "reactions", {
      subjects: withBlockSubjects(
        { doc: { table: "public.docs", idType: "uuid" } },
        modules,
        {},
      ),
      modules: { reactions: { on: ["doc"] } },
    });

    expect(sql).toContain(`when 'doc' then exists`);
    expect(sql).toContain(`when 'message' then exists`);
  });

  it("broadcasts on the topic option and checks it", () => {
    const sql = sqlOf(["reactions"], "reactions", {
      modules: { reactions: { options: { topic: "emoji" } } },
    });

    expect(sql).toContain(`like 'emoji:%'`);
    expect(() =>
      sqlOf(["reactions"], "reactions", {
        modules: { reactions: { options: { topic: "Bad Topic" } } },
      }),
    ).toThrow(/topic must be a lowercase name/);
  });

  it("stores the inbox's reactions on the message only when installed", () => {
    const alone = sqlOf(["messaging", "inbox"], "inbox");
    expect(alone).toContain("INBOX_REACTIONS_MISSING");
    const together = sqlOf(["messaging", "inbox", "reactions"], "inbox");
    expect(together).toContain(`insert into "better_supabase"."reactions"`);
    expect(together).not.toContain("INBOX_REACTIONS_MISSING");

    const step = (modules: readonly string[]): string =>
      upgradePlan(
        modules.map((module) => ({
          module,
          version: module === "inbox" ? 3 : 99,
        })),
      ).find((entry) => entry.module === "inbox")?.steps[0]?.sql ?? "";

    expect(step(["messaging", "attachments", "inbox"])).toContain(
      "reactions on messages are dropped",
    );
    const moved = step(["messaging", "attachments", "inbox", "reactions"]);
    expect(moved).toContain(`where x."subject_type" = 'inbox_message';`);
    expect(moved).toContain("cross join lateral jsonb_each(x.reactions) e");
  });
});
