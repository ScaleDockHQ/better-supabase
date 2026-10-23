import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { CONTENT } from "../../../src/sql/modules/content.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const render = (
  options: Readonly<Record<string, unknown>> = {},
  also: readonly string[] = [],
  module = "content",
): string =>
  renderBlocks(["content", ...also], { modules: { content: { options } } })
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("content module", () => {
  it("grants anon the two public reads and nothing else", () => {
    const sql = render();

    const anonGrants = sql
      .split("\n")
      .filter(
        (line) =>
          line.startsWith("grant execute") &&
          line.includes("anon") &&
          !line.includes("actor_"),
      );

    expect(anonGrants).toEqual([
      `grant execute on function "better_supabase"."public_content_entry"(uuid, text, text, text) to anon, authenticated, service_role;`,
      `grant execute on function "better_supabase"."public_content_entries"(uuid, text, text, integer, timestamptz) to anon, authenticated, service_role;`,
    ]);
    expect(sql).not.toMatch(/create policy [^\n]* to anon/);
  });

  it("keeps the slug unique per organization, type and locale", () => {
    const sql = render();

    expect(sql).toContain(`unique ("tenant_id", "type", "locale", "slug")`);
    expect(sql).toContain(
      `unique ("tenant_id", "translation_group_id", "locale")`,
    );
    expect(sql).toContain("CONTENT_SLUG_TAKEN");
  });

  it("checks types and locales against the options, the first locale being the default", () => {
    const sql = render({ types: ["article"], locales: ["nl", "en"] });

    expect(sql).toContain(`array['article']::text[]`);
    expect(sql).toContain(`array['nl', 'en']::text[]`);
    expect(sql).toContain(
      `coalesce(nullif(public_content_entry.locale, ''), 'nl')`,
    );
  });

  it("refuses invalid types and locales", () => {
    expect(() => render({ types: [] })).toThrow(/types must name/);
    expect(() => render({ types: ["Blog Post"] })).toThrow(/not a valid type/);
    expect(() => render({ locales: ["english"] })).toThrow(
      /not a valid locale/,
    );
    expect(() => render({ locales: ["en", "en"] })).toThrow(/twice/);
  });

  it("publishes directly unless requireApproval is on", () => {
    expect(render()).not.toContain("open_approval");
    expect(render({}, ["approvals"])).not.toContain("open_approval");

    const gated = render({ requireApproval: true }, ["approvals"]);

    expect(gated).toContain(`"better_supabase"."open_approval"(`);
    expect(gated).toContain(`"approvers":{"permission":"content.publish"}`);
  });

  it("needs the approvals block for requireApproval", () => {
    expect(() => render({ requireApproval: true })).toThrow(
      /requireApproval needs the approvals block/,
    );
  });

  it("takes a publish policy for the approval", () => {
    const sql = render(
      {
        requireApproval: true,
        publishPolicy: {
          steps: [{ approvers: { role: "editor" }, required: 2 }],
        },
      },
      ["approvals"],
    );

    expect(sql).toContain(`"approvers":{"role":"editor"},"required":2`);
    expect(() =>
      render(
        {
          requireApproval: true,
          publishPolicy: { steps: [], selfApproval: true },
        },
        ["approvals"],
      ),
    ).toThrow(/publishPolicy.steps/);
  });

  it("publishes approved requests through the approvals contribution", () => {
    const sql = render({ requireApproval: true }, ["approvals"], "approvals");

    expect(sql).toContain(
      `perform "better_supabase"."content_entry_approved"(`,
    );
  });

  it("records versions only with the versions block", () => {
    expect(render()).not.toContain("version_insert");

    const sql = render({}, ["versions"]);

    expect(sql).toContain(`null, null, 'auto', false, auth.uid());`);
    expect(sql).toContain(`null, 'published', 'manual', true, auth.uid());`);
  });

  it("links the cover image to attachments only when installed", () => {
    expect(render()).toContain("CONTENT_MEDIA_UNSUPPORTED");

    const sql = render({}, ["attachments"]);

    expect(sql).not.toContain("CONTENT_MEDIA_UNSUPPORTED");
    expect(sql).toContain(
      `"cover_attachment_id" uuid references "better_supabase"."attachments" ("id") on delete set null`,
    );
  });

  it("leaves the publish timer to the block schedules", () => {
    expect(render()).not.toContain("cron.schedule");
  });

  it("keeps the internal publish functions away from every API role", () => {
    const sql = render({ requireApproval: true }, ["approvals"]);

    expect(sql).toContain(
      `revoke execute on function "better_supabase"."content_entry_go_live"(uuid) from public, anon, authenticated;`,
    );
    expect(sql).toContain(
      `revoke execute on function "better_supabase"."content_entry_approved"(uuid) from public, anon, authenticated;`,
    );
    expect(sql).toContain(
      `grant execute on function "better_supabase"."publish_due_content_entries"() to service_role;`,
    );
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { content: { mode: "custom" } } };

    const sql = renderBlocks(["content"], custom)
      .filter((file) => file.module === "content")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("create table");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(CONTENT.build(context, {})).toBe("");
    const [contract] = customContracts(["content"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "create_content_entry",
        "publish_content_entry",
        "schedule_content_entry",
        "public_content_entry",
        "public_content_entries",
      ]),
    );
  });
});
