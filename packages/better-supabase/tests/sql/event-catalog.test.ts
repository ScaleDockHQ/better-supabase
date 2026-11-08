import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
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
      drive: { options: { drives: true } },
    },
  });

  // Rendered apart: the drive's document machine changes which state-machine
  // events the render above records.
  const controlled = renderBlocks(Object.keys(SQL_MODULES), {
    modules: { drive: { options: { control: { types: ["sop"] } } } },
  }).filter((file) => file.module === "drive-files");

  const byModule = new Map<string, Set<string>>();

  for (const file of [...files, ...controlled]) {
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

/**
 * Events only a module option turns on, and the chat share events, which the
 * share-links file records once that block is installed.
 */
const OPTIONAL = new Set([
  "ai_chat.shared",
  "ai_chat.share_revoked",
  "field_value.viewed",
  "subject.accessed",
  "field_value.deleted",
  "team.restored",
  "timesheet.rejected",
  "leave_request.rejected",
  "expense_report.rejected",
  "expense.created",
  "expense.submitted",
  "expense.approved",
  "expense.rejected",
  "expense.reimbursed",
  "expense.withdrawn",
  "expense.deleted",
  "object.uploaded",
  "pipeline.stage_changed",
  "calendar.updated",
  "approval_policy.created",
  "approval_policy.updated",
  "approval_policy.deleted",
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
    const past = /(ed|left|paid|set|sent|split|withdrawn)$/;
    expect(
      MAP_TYPES.filter(
        (type) =>
          !typeName.test(type) || !past.test(type) || type.includes("canceled"),
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
