import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

type Modules = BlockSqlLayout["modules"];

const render = (blocks: readonly string[], modules: Modules = {}) =>
  renderBlocks(blocks, { modules });

const sqlOf = (
  files: ReturnType<typeof renderBlocks>,
  module: string,
): string =>
  files
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const all = ["contacts", "relations", "guests"];

describe("representatives", () => {
  it("adds the represents kind to relations with a data check", () => {
    const relations = sqlOf(render(all), "relations");

    expect(relations).toContain(
      `('represents', 'represents', false, false, false, false, 'represented_by')`,
    );
    expect(relations).toContain(
      `if v_kind = 'represents' and not (v_source_type in ('person')) then`,
    );
    expect(relations).toContain(
      `if v_kind = 'represents' and not coalesce((jsonb_typeof(coalesce(link.data, '{}'::jsonb)) = 'object'`,
    );
    expect(relations).toContain("'legal_representative', 'guardian'");
    expect(relations).toContain("RELATION_DATA_INVALID");
    expect(sqlOf(render(["relations"]), "relations")).not.toContain(
      "represents",
    );
  });

  it("keeps the app's represents kind without the check", () => {
    const relations = sqlOf(
      render(all, {
        relations: { options: { kinds: { represents: { symmetric: true } } } },
      }),
      "relations",
    );

    expect(relations).toContain(
      `('represents', 'represents', false, false, false, true, 'represents')`,
    );
    expect(relations).not.toContain("RELATION_DATA_INVALID");
  });

  it("renders the representative functions only with relations", () => {
    const contacts = sqlOf(render(all), "contacts");

    expect(contacts).toContain(
      `create or replace function "better_supabase"."list_representatives"(subject_type text, subject_id text)`,
    );
    expect(contacts).toContain(
      `create or replace function "better_supabase"."represented_by_me"(tenant uuid)`,
    );
    expect(contacts).toContain("better_supabase.portal_parties()");

    const alone = sqlOf(render(["contacts"]), "contacts");

    expect(alone).not.toContain("list_representatives");
  });

  it("lets a representative's guest in only with the representation option", () => {
    expect(sqlOf(render(all), "guests")).not.toContain("'represents'");

    const guests = sqlOf(
      render(all, {
        guests: { options: { representation: { subjects: ["client"] } } },
      }),
      "guests",
    );

    expect(guests).toContain(`and r."kind" = 'represents'`);
    expect(guests).toContain(`r."target_type" in ('client')`);
    expect(guests).toContain(`portal_subjects.action in ('comment', 'upload')`);
  });

  it("rejects a representation option it can't render", () => {
    const representation =
      (value: unknown, blocks = all) =>
      () =>
        render(blocks, { guests: { options: { representation: value } } });

    expect(representation({ subjects: [] })).toThrow(/non-empty list/);
    expect(representation({ subjects: ["Client"] })).toThrow(/non-empty list/);
    expect(
      representation({ subjects: ["client"] }, ["contacts", "guests"]),
    ).toThrow(/needs the relations and contacts blocks/);
  });
});
