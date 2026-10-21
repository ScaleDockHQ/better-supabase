import { describe, expect, it } from "vitest";

import { withBlockSubjects } from "../../../src/config/block-subjects.ts";
import { renderModules } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderModules>[1];

const sqlOf = (
  modules: readonly string[],
  module: string,
  layout: Layout = {},
): string =>
  renderModules(modules, layout)
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

  it("sees comments and inbox messages through their own policies", () => {
    const modules = ["reactions", "comments", "inbox"];

    const sql = sqlOf(modules, "reactions", {
      subjects: withBlockSubjects({}, modules, {}),
    });

    expect(sql).toContain(
      `when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."deleted_at" is null)`,
    );
    expect(sql).toContain(
      `when 'inbox_message' then exists (select 1 from "better_supabase"."inbox_messages" m`,
    );
    expect(sql).toContain(`react_to_message"(react.subject_id::uuid`);
    expect(
      renderModules(["reactions", "comments", "inbox"]).some((file) =>
        file.contents.includes("Copies the reactions inbox messages kept"),
      ),
    ).toBe(true);
  });

  it("keeps comments when options.subjects lists other types", () => {
    const modules = ["reactions", "comments"];

    const sql = sqlOf(modules, "reactions", {
      subjects: withBlockSubjects(
        { doc: { table: "public.docs", idType: "uuid" } },
        modules,
        {},
      ),
      modules: { reactions: { options: { subjects: ["doc"] } } },
    });

    expect(sql).toContain(`when 'doc' then exists`);
    expect(sql).toContain(`when 'comment' then exists`);
  });

  it("follows a renamed comment entity", () => {
    const modules = ["reactions", "comments"];
    const blocks = { comments: { entities: { comment: "note" } } };

    const sql = sqlOf(modules, "reactions", {
      subjects: withBlockSubjects({}, modules, blocks),
      modules: blocks,
    });

    expect(sql).toContain(`when 'note' then exists`);
    expect(sql).not.toContain(`when 'comment'`);
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

  it("moves the inbox's reactions to its table only when installed", () => {
    const alone = sqlOf(["inbox"], "inbox");
    expect(alone).toContain("jsonb_build_object(emoji");
    const together = sqlOf(["inbox", "reactions"], "inbox");
    expect(together).toContain(`insert into "better_supabase"."reactions"`);
    expect(together).not.toContain("jsonb_build_object(emoji");
  });
});
