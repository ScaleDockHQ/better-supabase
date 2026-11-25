import { describe, expect, it } from "vitest";

import type { Finding } from "../../../src/cli/doctor/rules.ts";

import { formatReport } from "../../../src/cli/doctor/format.ts";
import { readSetFor } from "../../../src/cli/doctor/round-trips.ts";

const finding = (code: string, severity: Finding["severity"]): Finding => ({
  code,
  severity,
  title: `title ${code}`,
  message: "m",
  help: "h",
});

const report = (findings: Finding[]): string =>
  formatReport(findings, {
    format: "text",
    rules: [],
    version: "0",
    fallbackFile: "x",
    phases: [{ name: "run the rules", ms: 1500 }],
  });

describe("doctor text report", () => {
  it("starts a long report with one line per rule, worst first, then by count", () => {
    const findings = [
      ...Array.from({ length: 15 }, () => finding("BS200", "info")),
      ...Array.from({ length: 4 }, () => finding("BS643", "warning")),
      ...Array.from({ length: 2 }, () => finding("BS385", "warning")),
    ];

    const lines = report(findings).split("\n");

    expect(
      lines.slice(0, 3).map((line) => line.split(/\s+/).slice(0, 3)),
    ).toEqual([
      ["warning", "BS643", "4"],
      ["warning", "BS385", "2"],
      ["info", "BS200", "15"],
    ]);
  });

  it("leaves a short report as it was, and prints the phase times", () => {
    const text = report([finding("BS200", "info")]);

    expect(text.startsWith("info    BS200 title BS200")).toBe(true);
    expect(text).toContain("Time: run the rules 1.5 s.");
  });
});

describe("BS609 read set", () => {
  it("names each read after its table and swaps db for the builder", () => {
    const code = readSetFor("src/app/tasks/page.tsx", [
      "db.tasks.list({ limit: 5 })",
      "ctx.db.tasks.count()",
      "db.projects.list()",
    ]);

    expect(code).toContain('defineReadSet(betterSupabase, "tasks_page"');
    expect(code).toContain("tasks: s.tasks.list({ limit: 5 }),");
    expect(code).toContain("tasks2: s.tasks.count(),");
    expect(code).toContain("projects: s.projects.list(),");
    expect(code).toContain(
      "const { tasks, tasks2, projects } = await db.$many(tasksPage",
    );
  });
});
