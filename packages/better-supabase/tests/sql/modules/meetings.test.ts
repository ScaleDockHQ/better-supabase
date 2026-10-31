import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { MEETINGS } from "../../../src/sql/modules/meetings.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = [
  "memberships",
  "permissions",
  "subjects",
  "tasks",
  "calendar",
  "meetings",
];

const sqlOf = (
  layout: Layout = {},
  modules: readonly string[] = BASE,
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "meetings")
    .map((file) => file.contents)
    .join("\n");

const withOptions = (options: Record<string, unknown>): Layout => ({
  modules: { meetings: { options } },
});

describe("meetings module", () => {
  it("renders the tables, the one chair rule and the attendee read policy", () => {
    const sql = sqlOf();

    expect(sql).toContain("meeting_attendees");
    expect(sql).toContain("meeting_agenda_items");
    expect(sql).toContain("meeting_decisions");
    expect(sql).toContain("meeting_action_items");
    expect(sql).toContain("meeting_role");
    expect(sql).toContain("array['meeting', 'board'");
  });

  it("checks the kinds from the options", () => {
    const sql = sqlOf(withOptions({ kinds: ["standup"] }));

    expect(sql).toContain("array['standup']::text[]");
    expect(sql).not.toContain("'board'");
    expect(() => sqlOf(withOptions({ kinds: [] }))).toThrow("at least one");
    expect(() => sqlOf(withOptions({ kinds: ["Board"] }))).toThrow("lowercase");
    expect(() => sqlOf(withOptions({ kinds: ["a", "a"] }))).toThrow("twice");
  });

  it("settles a decision from the votes and creates action items as tasks", () => {
    const sql = sqlOf({}, [...BASE.slice(0, -1), "reactions", "meetings"]);

    expect(sql).toContain("vote_tally");
    expect(sql).toContain("create_task");
  });

  it("mirrors meetings to the named calendar only when asked to", () => {
    expect(sqlOf()).not.toContain("meeting_calendar_mirror");

    const sql = sqlOf(withOptions({ calendar: "Meetings" }));

    expect(sql).toContain("meeting_calendar_mirror");
    expect(sql).toContain("'Meetings'");
    expect(sql).toContain("'meeting-' ||");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { meetings: { mode: "custom" } } };
    expect(sqlOf(custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(MEETINGS.build(context, {})).toBe("");
    const [contract] = customContracts(["meetings"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "create_meeting",
        "hold_meeting",
        "record_meeting_decision",
        "add_meeting_action_item",
      ]),
    );
  });
});
