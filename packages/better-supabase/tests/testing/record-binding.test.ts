import { describe, expect, it } from "vitest";

import type { AnyRecordBinding } from "../../src/blocks/record-bindings.ts";

import { commentsBinding } from "../../src/blocks/comments/record-binding.ts";
import { defineRecordBinding } from "../../src/blocks/record-bindings.ts";
import { ConformanceError } from "../../src/testing/conformance.ts";
import { testRecordBinding } from "../../src/testing/index.ts";
import { failed, resolved } from "../fixtures/ports.ts";

const customer = { type: "customer", id: "7" };

const fake = {
  list: () => resolved([]),
  counts: () => resolved({ "customer:7": 3 }),
};

async function failures(
  binding: AnyRecordBinding,
  client: unknown = fake,
): Promise<string[]> {
  const error = await testRecordBinding("broken", binding, {
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

describe("testRecordBinding", () => {
  it("passes the comments binding against a fake client", async () => {
    const report = await testRecordBinding("comments", commentsBinding, {
      client: fake,
      subject: customer,
    });

    expect(report.subject).toBe('Record binding "comments"');
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(report.checks.map((check) => check.name)).toContain(
      "counts records by subject key",
    );
  });

  it("fails a binding that breaks the contract", async () => {
    const broken = {
      ...defineRecordBinding({
        permissions: { read: "" },
        load: () => failed<number>("gone"),
        count: () => resolved({ other: 1.5 }),
        events: [""],
      }),
      apiVersion: 2,
    } as unknown as AnyRecordBinding;

    expect(await failures(broken)).toEqual([
      "has apiVersion 1",
      "names a read permission",
      "lists event types",
      "loads a record",
      "counts records by subject key",
    ]);
  });

  it("skips the count check for a binding without count", async () => {
    const report = await testRecordBinding(
      "plain",
      defineRecordBinding({
        permissions: { read: "read" },
        load: () => resolved(1),
      }),
      { client: {}, subject: customer, subjects: [customer] },
    );

    expect(report.checks.map((check) => check.name)).not.toContain(
      "counts records by subject key",
    );
  });

  it("fails a count that errors", async () => {
    const binding = defineRecordBinding({
      permissions: { read: "read" },
      load: () => resolved(1),
      count: () => failed<Readonly<Record<string, number>>>("down"),
    });

    expect(await failures(binding)).toEqual(["counts records by subject key"]);
  });
});
