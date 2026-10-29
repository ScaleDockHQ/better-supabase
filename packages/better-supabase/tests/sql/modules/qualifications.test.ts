import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { QUALIFICATIONS } from "../../../src/sql/modules/qualifications.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["subjects", "qualifications"];

const ALL = [
  "subjects",
  "attachments",
  "notifications",
  "teams",
  "employees",
  "contacts",
  "assets",
  "segments",
  "courses",
  "qualifications",
];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "qualifications")
    .map((file) => file.contents)
    .join("\n");

describe("qualifications module", () => {
  it("grants from course certificates only with courses installed", () => {
    const sql = sqlOf(ALL);
    expect(sql).toContain("after insert or update of");
    expect(sql).toMatch(/on "better_supabase"\."course_certificates"/);
    expect(sql).toMatch(
      /"course_id" uuid references "better_supabase"\."courses"/,
    );

    const bare = sqlOf();
    expect(bare).not.toContain("course_certificates");
    expect(bare).toContain("course_id needs the courses block");
  });

  it("reads each requirement target from the block behind it", () => {
    const sql = sqlOf(ALL);
    expect(sql).toContain("when 'team' then");
    expect(sql).toContain("when 'job_title' then");
    expect(sql).toContain("when 'asset_kind' then");
    expect(sql).toContain("when 'segment' then");

    const bare = sqlOf();
    expect(bare).not.toContain("when 'team' then");
    expect(bare).toContain("team requirements need the teams block");
    expect(bare).toContain("company holders need the contacts block");
    expect(bare).toContain("the teamId filter needs the teams block");
  });

  it("links evidence to an attachment only with attachments installed", () => {
    expect(sqlOf(ALL)).toMatch(
      /"evidence_attachment_id" uuid references "better_supabase"\."attachments"/,
    );
    expect(sqlOf()).toContain("evidence files need the attachments block");
  });

  it("notifies expiring holdings only with notifications installed", () => {
    expect(sqlOf(ALL)).toContain("'qualification.' || v_status || ':'");
    expect(sqlOf()).not.toContain("'qualification.' || v_status || ':'");
  });

  it("takes the renewal window and holder types from the options", () => {
    const sql = sqlOf(BASE, {
      modules: {
        qualifications: {
          options: { renewalWindowDays: 60, holderTypes: ["member"] },
        },
      },
    });

    expect(sql).toContain("current_date + 60");
    expect(sql).toContain("holder_types takes member");

    expect(() =>
      sqlOf(BASE, {
        modules: { qualifications: { options: { holderTypes: ["robot"] } } },
      }),
    ).toThrow("blocks.qualifications.options.holderTypes takes");
    expect(() =>
      sqlOf(BASE, {
        modules: { qualifications: { options: { renewalWindowDays: -1 } } },
      }),
    ).toThrow("renewalWindowDays");
  });

  it("writes extra columns on the holdings through grant_qualification", () => {
    const sql = sqlOf(BASE, {
      modules: {
        qualifications: {
          options: { extraColumns: { licence_number: "text" } },
        },
      },
    });

    expect(sql).toContain(
      `alter table "better_supabase"."qualifications" add column if not exists "licence_number" text;`,
    );
    expect(sql).toContain("evidence_note text default null, fields jsonb");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { qualifications: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(QUALIFICATIONS.build(context, {})).toBe("");
    const [contract] = customContracts(["qualifications"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "qualification_gaps",
        "qualified_holders",
        "grant_qualification",
      ]),
    );
  });
});
