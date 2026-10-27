import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
import { BLOCK_EVENT_RENAMES } from "../../src/core/block-events.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const source = (path: string): string =>
  readFileSync(new URL(path, import.meta.url), "utf-8");

/** Every block's event types. */
const MAP_TYPES = [
  ...new Set(BLOCK_MANIFESTS.flatMap((block) => block.events.types)),
];

/** The manifest that owns each SQL module. */
const OWNER = new Map(
  BLOCK_MANIFESTS.flatMap((block) =>
    block.sql.map((module) => [module, block] as const),
  ),
);

/** Rendered with every module, so each optional event path is on. */
const RECORDED = (() => {
  const files = renderBlocks(Object.keys(SQL_MODULES), {
    modules: {
      audit: { options: { restricted: true } },
      bookings: { options: { recurring: true } },
      memberships: { options: { roles: { many: true } } },
      content: { options: { requireApproval: true } },
      activities: { options: { recordings: true } },
      orders: { options: { kitchen: true } },
      passes: { options: { credits: true } },
    },
  });

  const byModule = new Map<string, Set<string>>();

  for (const file of files) {
    // An audit-only event (`ctx.audit`) reaches the audit log, not the outbox.
    for (const match of file.contents.matchAll(
      /(?:emit_event\(|audit_event\(\s*event_type => )'([a-z_.]+)'/g,
    )) {
      const types = byModule.get(file.module) ?? new Set<string>();
      types.add(match[1] ?? "");
      byModule.set(file.module, types);
    }
  }

  return byModule;
})();

/** Events only a module option turns on. */
const OPTIONAL = new Set([
  "field_value.viewed",
  "field_value.deleted",
  "team.restored",
  "timesheet.rejected",
  "leave.rejected",
  "expense_report.rejected",
  "object.uploaded",
  "pipeline.stage_changed",
  "calendar.updated",
]);

const declared = (module: string): string[] =>
  Object.keys(SQL_MODULES[module]?.names?.events ?? {});

describe("SQL module event catalog", () => {
  it("declares the events of every module that records one", () => {
    expect(RECORDED.size).toBeGreaterThan(20);

    const mismatches = [...RECORDED].flatMap(([module, types]) => {
      const catalog = declared(module);

      if (catalog.length === 0) {
        return [`${module}: no catalog`];
      }

      return catalog
        .filter((type) => !types.has(type) && !OPTIONAL.has(type))
        .map((type) => `${module}: ${type} is never recorded`);
    });

    expect(mismatches).toEqual([]);
  });

  it("declares only types in its block's event map", () => {
    const unknown = Object.keys(SQL_MODULES).flatMap((module) => {
      const known = new Set(OWNER.get(module)?.events.types);

      return declared(module)
        .filter((type) => !known.has(type))
        .map((type) => `${module}: ${type}`);
    });

    expect(unknown).toEqual([]);
  });

  it("names events <entity>.<past_verb>, spelled one way", () => {
    const typeName = /^[a-z]+(_[a-z]+)*\.[a-z]+(_[a-z]+)*$/;
    const past = /(ed|left|paid|set|sent)$/;
    expect(
      MAP_TYPES.filter(
        (type) =>
          !typeName.test(type) || !past.test(type) || type.includes("canceled"),
      ),
    ).toEqual([]);
  });

  it("maps every renamed type to a current one", () => {
    const known = new Set(MAP_TYPES);
    expect(
      Object.entries(BLOCK_EVENT_RENAMES).filter(
        ([from, to]) => known.has(from) || !known.has(to),
      ),
    ).toEqual([]);
  });

  it("lists every type on the events docs page", () => {
    const docs = source(
      "../../../../apps/docs/content/docs/(reference)/extending/events.mdx",
    );

    expect(MAP_TYPES.filter((type) => !docs.includes(`\`${type}\``))).toEqual(
      [],
    );
  });
});
