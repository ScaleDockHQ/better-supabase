import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import {
  checkLanes,
  checkMissingRows,
  checkRowFloor,
  countStates,
  expandIds,
  namedIds,
  parseFindings,
  parseLanes,
  renderCounts,
  replaceCounts,
  stateOf,
} from "./check-example-findings.ts";

const HEADER = [
  "| Id | Found on | Kind | State | Item |",
  "| -- | -- | -- | -- | -- |",
];

const table = (...rows: string[]): string => [...HEADER, ...rows].join("\n");

describe("check-example-findings", () => {
  it("reads the state of a cell", () => {
    expect(stateOf("fixed (PR #1)")).toBe("fixed");
    expect(stateOf("partly fixed (this PR)")).toBe("partly fixed");
    expect(stateOf("measured (ADR 0686)")).toBe("measured away");
    expect(stateOf("deferred")).toBe("deferred");
    expect(stateOf("later")).toBeUndefined();
  });

  it("expands ids and ranges and keeps leading zeros", () => {
    expect(expandIds("EX-001 to EX-003, EX-1200")).toEqual([
      "EX-001",
      "EX-002",
      "EX-003",
      "EX-1200",
    ]);
  });

  it("counts the states", () => {
    const { rows } = parseFindings(
      table(
        "| EX-1 | a | bug | fixed (PR #1) | x |",
        "| EX-2 | a | bug | deferred (needs x) | x |",
      ),
    );

    expect(countStates(rows).fixed).toBe(1);
    expect(renderCounts(rows)).toContain("2 findings: 1 fixed");
    expect(renderCounts(rows)).toContain("(1 unfinished)");
  });

  it("reports a header row, a blank row and a duplicate id inside a table", () => {
    const { problems } = parseFindings(
      table(
        "| EX-1 | a | bug | fixed | x |",
        "| Id | Found on | Kind | State | Item |",
        "| EX-1 | a | bug | fixed | x |",
        "|  |  |  |  |  |",
      ),
    );

    expect(problems.some((line) => line.includes("header row"))).toBe(true);
    expect(problems.some((line) => line.includes("repeats EX-1"))).toBe(true);
    expect(problems.some((line) => line.includes("not a finding row"))).toBe(
      true,
    );
  });

  it("rewrites the counts between the markers", () => {
    const { rows } = parseFindings(table("| EX-1 | a | bug | open | x |"));

    const text =
      "a\n<!-- example-findings:counts:start -->\nold\n<!-- example-findings:counts:end -->\nb";

    expect(replaceCounts(text, rows)).toContain("1 open");
    expect(replaceCounts("no markers", rows)).toBeUndefined();
  });

  it("reads lanes and their findings", () => {
    const lanes = parseLanes(
      [
        "### Lane X1",
        "",
        "- Status: planned",
        "- Findings: EX-1, EX-3 to EX-4",
        "",
        "## Next",
        "- Findings: EX-9",
      ].join("\n"),
    );

    expect(lanes).toEqual([
      { name: "X1", status: "planned", findings: ["EX-1", "EX-3", "EX-4"] },
    ]);
  });

  it("fails on an unnamed unfinished row and on a merged lane with one", () => {
    const { rows } = parseFindings(
      table(
        "| EX-1 | a | bug | deferred | x |",
        "| EX-2 | a | bug | fixed | x |",
        "| EX-3 | a | bug | open | x |",
      ),
    );

    const problems = checkLanes(rows, [
      { name: "X1", status: "merged", findings: ["EX-1", "EX-2"] },
    ]);

    expect(problems).toEqual([
      expect.stringContaining("named by no lane's Findings line: EX-3"),
      "Lane X1 is merged but EX-1 is unfinished",
    ]);
  });

  it("lets a merged lane keep a row that waits on a maintainer step", () => {
    const { rows } = parseFindings(
      table(
        "| EX-1 | a | bug | deferred (needs: Stripe keys) | x |",
        "| EX-2 | a | bug | deferred (a library change) | x |",
      ),
    );

    expect(
      checkLanes(rows, [
        { name: "X1", status: "merged", findings: ["EX-1", "EX-2"] },
      ]),
    ).toEqual(["Lane X1 is merged but EX-2 is unfinished"]);
  });

  it("fails when a lane names an id that has no row", () => {
    const { rows } = parseFindings(
      table("| EX-1 | a | bug | fixed (PR #1) | x |"),
    );

    const tracker = [
      "## Progress",
      "### Lane X1",
      "- Findings: EX-1, EX-2",
      "- Log: covers EX-5 to EX-6",
      "## Lane ownership",
      "EX-90 to EX-91",
    ].join("\n");

    const lanes = parseLanes(tracker);
    const named = namedIds(lanes, tracker);

    expect([...named]).toEqual(["EX-1", "EX-2", "EX-5", "EX-6"]);
    expect(checkMissingRows(rows, named)).toEqual([
      expect.stringContaining("EX-2, EX-5, EX-6"),
    ]);
    expect(checkMissingRows(rows, new Set(["EX-1"]))).toEqual([]);
  });

  it("fails when the row count drops below the floor", () => {
    const { rows } = parseFindings(
      table("| EX-1 | a | bug | fixed (PR #1) | x |"),
    );

    expect(checkRowFloor(rows, 1)).toEqual([]);
    expect(checkRowFloor(rows, 2)).toEqual([
      expect.stringContaining("floor of 2"),
    ]);
  });

  it("holds for the committed report and tracker", () => {
    const { rows, problems } = parseFindings(
      readFileSync("docs/agents/example-findings.md", "utf-8"),
    );

    const lanes = parseLanes(
      readFileSync("docs/agents/block-consistency-audit.md", "utf-8"),
    );

    expect(problems).toEqual([]);
    expect(checkLanes(rows, lanes)).toEqual([]);

    const tracker = readFileSync(
      "docs/agents/block-consistency-audit.md",
      "utf-8",
    );

    const floor = Number(
      readFileSync("docs/agents/example-findings.count", "utf-8"),
    );

    expect(checkMissingRows(rows, namedIds(lanes, tracker))).toEqual([]);
    expect(checkRowFloor(rows, floor)).toEqual([]);
  });
});
