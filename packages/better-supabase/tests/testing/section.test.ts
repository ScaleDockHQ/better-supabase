import { describe, expect, it } from "vitest";

import type { AnySection } from "../../src/blocks/sections.ts";

import { commentsSection } from "../../src/blocks/comments/section.ts";
import { defineSection } from "../../src/blocks/sections.ts";
import { ConformanceError } from "../../src/testing/conformance.ts";
import { testSection } from "../../src/testing/index.ts";
import { failed, resolved } from "../fixtures/ports.ts";

const customer = { type: "customer", id: "7" };

const fake = {
  list: () => resolved([]),
  counts: () => resolved({ "customer:7": 3 }),
};

async function failures(
  section: AnySection,
  client: unknown = fake,
): Promise<string[]> {
  const error = await testSection("broken", section, {
    client,
    subject: customer,
  }).then(
    () => undefined,
    (cause: unknown) => cause,
  );

  expect(error).toBeInstanceOf(ConformanceError);

  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => check.name);
}

describe("testSection", () => {
  it("passes the comments section against a fake client", async () => {
    const report = await testSection("comments", commentsSection, {
      client: fake,
      subject: customer,
    });

    expect(report.subject).toBe('Section "comments"');
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(report.checks.map((check) => check.name)).toContain(
      "counts records by subject key",
    );
  });

  it("fails a section that breaks the contract", async () => {
    const broken = {
      ...defineSection({
        permissions: { read: "" },
        load: () => failed<number>("gone"),
        count: () => resolved({ other: 1.5 }),
        events: [""],
      }),
      apiVersion: 2,
    } as unknown as AnySection;

    expect(await failures(broken)).toEqual([
      "has apiVersion 1",
      "names a read permission",
      "lists event types",
      "loads a record",
      "counts records by subject key",
    ]);
  });

  it("skips the count check for a section without count", async () => {
    const report = await testSection(
      "plain",
      defineSection({ permissions: { read: "read" }, load: () => resolved(1) }),
      { client: {}, subject: customer, subjects: [customer] },
    );

    expect(report.checks.map((check) => check.name)).not.toContain(
      "counts records by subject key",
    );
  });

  it("fails a count that errors", async () => {
    const section = defineSection({
      permissions: { read: "read" },
      load: () => resolved(1),
      count: () => failed<Readonly<Record<string, number>>>("down"),
    });

    expect(await failures(section)).toEqual(["counts records by subject key"]);
  });
});
