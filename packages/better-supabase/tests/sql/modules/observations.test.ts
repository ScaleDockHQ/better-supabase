import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { OBSERVATIONS } from "../../../src/sql/modules/observations.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["subjects", "observations"];

const ALL = ["subjects", "notifications", "forms", "observations"];

const files = (modules: readonly string[] = BASE, layout: Layout = {}) =>
  renderBlocks(modules, layout).filter(
    (file) => file.module === "observations",
  );

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  files(modules, layout)
    .map((file) => file.contents)
    .join("\n");

describe("observations module", () => {
  it("keeps the vital signs out unless defaults is vitals", () => {
    expect(sqlOf()).not.toContain("8867-4");

    const vitals = files(BASE, {
      modules: { observations: { options: { defaults: "vitals" } } },
    })
      .filter((file) => file.kind === "data")
      .map((file) => file.contents)
      .join("\n");

    expect(vitals).toContain("'8867-4'");
    expect(vitals).toContain('"unit":"mm[Hg]"');
    expect(vitals).toContain("'http://loinc.org'");
    expect(vitals).toContain("on conflict");
  });

  it("rejects an unknown defaults set", () => {
    expect(() =>
      sqlOf(BASE, {
        modules: { observations: { options: { defaults: "labs" } } },
      }),
    ).toThrow(/defaults/);
  });

  it("maps form submissions only with forms installed", () => {
    const sql = sqlOf(ALL);
    expect(sql).toContain("observations_from_submission");
    expect(sql).toMatch(
      /after insert or update of "status" on "better_supabase"\."form_submissions"/,
    );
    expect(sql).toMatch(
      /"submission_id" uuid references "better_supabase"\."form_submissions"/,
    );

    const bare = sqlOf();
    expect(bare).not.toContain("observations_from_submission");
    expect(bare).not.toContain("form_submissions");
  });

  it("alerts the record team's leads only with notifications installed", () => {
    expect(sqlOf(ALL)).toContain("'observation.critical_recorded'");
    expect(sqlOf(ALL)).toContain('"better_supabase"."notify"(');
    expect(sqlOf()).not.toContain('"better_supabase"."notify"(');
  });

  it("partitions by month and drops the keys a partition can't hold", () => {
    const plain = sqlOf();
    expect(plain).toMatch(/"replaces_id" uuid references/);
    expect(plain).toMatch(
      /create unique index if not exists "observations_external_key"/,
    );

    const sql = sqlOf(BASE, {
      modules: { observations: { options: { partitioned: true } } },
    });

    expect(sql).toContain("partition by range");
    expect(sql).toContain('primary key ("id", "created_at")');
    expect(sql).not.toMatch(/"replaces_id" uuid references/);
    expect(sql).not.toMatch(
      /create unique index if not exists "observations_external_key"/,
    );
    expect(sql).toContain("pg_advisory_xact_lock");
  });

  it("reads observations through the subject check", () => {
    expect(sqlOf()).toContain("can_subject");
  });

  it("adds the extra columns to record and amend", () => {
    const sql = sqlOf(BASE, {
      modules: {
        observations: { options: { extraColumns: { ward: "text" } } },
      },
    });

    expect(sql).toContain('"ward" text');
    expect(sql).toContain("record_observation.fields");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { observations: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(OBSERVATIONS.build(context, {})).toBe("");
    const [contract] = customContracts(["observations"], custom);
    const names = contract?.functions.map((fn) => fn.name) ?? [];
    expect(names).toEqual(
      expect.arrayContaining(["record_observation", "observation_series"]),
    );
    expect(names).not.toContain("observations_from_submission");
  });
});
