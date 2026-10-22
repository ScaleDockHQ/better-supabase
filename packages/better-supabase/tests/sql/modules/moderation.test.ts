import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { MODERATION } from "../../../src/sql/modules/moderation.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (
  modules: readonly string[],
  layout: Layout = {},
  module = "moderation",
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === module && file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");

describe("moderation module", () => {
  it("hides content after three reports by default, with the default reasons", () => {
    const sql = sqlOf(["moderation"]);

    expect(sql).toContain('"open_reports" >= 3');
    expect(sql).toContain("'Hidden after 3 reports'");
    expect(sql).toContain(
      "'spam', 'abuse', 'harassment', 'off_topic', 'illegal', 'other'",
    );
    expect(sql).not.toContain("comments_moderation");
  });

  it("guards messages, comments included, when messaging is installed", () => {
    const modules = ["messaging", "comments", "moderation"];
    const sql = sqlOf(modules);
    const messages = sqlOf(modules, {}, "messaging");

    expect(sql).toContain("a removed message can''t be restored");
    expect(messages).toContain('create policy "messages_moderation"');
    expect(messages).toContain(
      '"better_supabase"."moderation_hidden"(\'message\'',
    );
    expect(messages).toContain('before insert on "better_supabase"."messages"');
  });

  it("takes the threshold and the reasons from the options", () => {
    const off = sqlOf(["moderation"], {
      modules: {
        moderation: { options: { autoHideThreshold: 0, reasons: ["spam"] } },
      },
    });

    expect(off).not.toContain("auto_hide', 'Hidden after");
    expect(off).toContain("reason must be one of spam");

    expect(() =>
      sqlOf(["moderation"], {
        modules: { moderation: { options: { autoHideThreshold: 1.5 } } },
      }),
    ).toThrow(
      "blocks.moderation.options.autoHideThreshold must be a whole number",
    );
    expect(() =>
      sqlOf(["moderation"], {
        modules: { moderation: { options: { reasons: [] } } },
      }),
    ).toThrow("blocks.moderation.options.reasons must list lower-case keys");
    expect(() =>
      sqlOf(["moderation"], {
        modules: { moderation: { options: { reasons: ["Spam!"] } } },
      }),
    ).toThrow("blocks.moderation.options.reasons must list lower-case keys");
  });

  it("moves review decisions onto moderation items", () => {
    const sql = sqlOf(["moderation", "reviews"], {}, "reviews");

    expect(sql).toContain('"better_supabase"."moderation_track"(');
    expect(sql).toContain('"better_supabase"."moderation_apply"(');
    expect(sql).not.toContain("moderated_by");
  });

  it("upgrades version 1 reviews and backfills their items", () => {
    const upgrade = (layout: Layout = {}): string =>
      (upgradePlan([{ module: "reviews", version: 1 }], layout)[0]?.steps ?? [])
        .map((step) => step.sql)
        .join("\n");

    const managed = upgrade();

    expect(managed).toContain(
      'create table if not exists "better_supabase"."moderation_items"',
    );
    expect(managed).toContain(
      "drop column moderated_by, drop column moderated_at",
    );
    expect(
      upgrade({ modules: { moderation: { mode: "custom" } } }),
    ).not.toContain("create table");
    expect(upgrade({ modules: { reviews: { mode: "custom" } } })).not.toContain(
      "moderated_by",
    );

    const data = (layout: Layout = {}): string =>
      renderBlocks(["moderation", "reviews"], layout)
        .filter((file) => file.module === "reviews" && file.kind === "data")
        .map((file) => file.contents)
        .join("\n");

    expect(data()).toContain(
      "Puts the reviews written before the moderation module under it.",
    );
    expect(data({ modules: { reviews: { mode: "custom" } } })).not.toContain(
      "Puts the reviews",
    );
  });

  it("leaves comments alone when the app manages them", () => {
    expect(
      sqlOf(["comments", "moderation"], {
        modules: { comments: { mode: "custom" } },
      }),
    ).not.toContain("comments_moderation");
    expect(
      sqlOf(
        ["moderation", "reviews"],
        { modules: { reviews: { mode: "custom" } } },
        "reviews",
      ),
    ).toBe("");
  });

  it("renders nothing for custom mode", () => {
    expect(
      sqlOf(["moderation"], { modules: { moderation: { mode: "custom" } } }),
    ).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const custom = { mode: "custom" } as unknown as BlockSqlContext;

    expect(MODERATION.build(custom, {})).toBe("");
  });
});
