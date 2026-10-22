import { describe, expect, it } from "vitest";

import type { RecordFormResult } from "../../src/records/index.ts";

import { entitySchema } from "../../src/blocks/entity-schema.ts";
import { workItemInputSchema } from "../../src/blocks/tasks/schemas.ts";
import { providedTemporal, provideTemporal } from "../../src/core/temporal.ts";
import { recordForm } from "../../src/records/index.ts";

interface Everything {
  id: string;
  name: string;
  count?: number;
  amount?: bigint;
  ratio?: number | null;
  active?: boolean;
  day?: string;
  stamp?: string;
  at?: Temporal.Instant;
  on?: Temporal.PlainDate;
  local?: Temporal.PlainDateTime;
  status?: "open" | "closed";
  tags?: ("a" | "b")[];
  data?: unknown;
  extra?: unknown;
  whatever?: unknown;
  createdAt?: string;
}

const everything = entitySchema<Everything>({
  fields: {
    id: { kind: "uuid" },
    name: {
      kind: "string",
      minLength: 1,
      maxLength: 20,
      description: "Shown on the card",
    },
    count: { kind: "integer", optional: true, minimum: 0, maximum: 9 },
    amount: { kind: "bigint", optional: true },
    ratio: { kind: "number", optional: true, nullable: true },
    active: { kind: "boolean", optional: true },
    day: { kind: "date", optional: true },
    stamp: { kind: "datetime", optional: true },
    at: { kind: "instant", optional: true },
    on: { kind: "plainDate", optional: true },
    local: { kind: "plainDateTime", optional: true },
    status: { kind: "enum", values: ["open", "closed"], optional: true },
    tags: { kind: "enum", values: ["a", "b"], array: true, optional: true },
    data: { kind: "json", optional: true },
    extra: { kind: "custom", optional: true },
    whatever: { kind: "unknown", optional: true },
    createdAt: { kind: "datetime", optional: true, readOnly: true },
  },
});

function valuesOf<T>(result: RecordFormResult<T>) {
  if (!result.ok) {
    throw new Error(JSON.stringify(result.errors));
  }

  return result;
}

describe("recordForm", () => {
  it("lists one field per writable key with its input, bounds and options", () => {
    const form = recordForm(everything);

    expect(form.fields.map((field) => [field.key, field.input])).toEqual([
      ["id", "text"],
      ["name", "text"],
      ["count", "integer"],
      ["amount", "integer"],
      ["ratio", "number"],
      ["active", "bool"],
      ["day", "date"],
      ["stamp", "datetime"],
      ["at", "datetime"],
      ["on", "date"],
      ["local", "datetime"],
      ["status", "option"],
      ["tags", "multi"],
      ["data", "json"],
      ["extra", "json"],
      ["whatever", "json"],
    ]);
    expect(form.fields[1]).toEqual({
      key: "name",
      label: "Name",
      input: "text",
      required: true,
      source: "entity",
      description: "Shown on the card",
      minLength: 1,
      maxLength: 20,
    });
    expect(form.fields[2]).toMatchObject({
      required: false,
      minimum: 0,
      maximum: 9,
    });
    expect(form.fields[11]).toMatchObject({ options: ["open", "closed"] });
  });

  it("picks and labels fields and appends the tenant's custom fields", () => {
    const form = recordForm(workItemInputSchema, {
      fields: ["title", "dueAt"],
      labels: { title: "Summary", region: "Area" },
      customFields: [
        { key: "region", label: "Region", type: "option", required: true },
        {
          key: "salary",
          label: "Salary",
          type: "currency",
          required: false,
          sensitive: true,
        },
        { key: "legacy", label: "Legacy", type: "free_text", required: false },
      ],
    });

    expect(
      form.fields.map((field) => [
        field.key,
        field.label,
        field.input,
        field.source,
      ]),
    ).toEqual([
      ["title", "Summary", "text", "entity"],
      ["dueAt", "Due at", "datetime", "entity"],
      ["region", "Area", "option", "custom"],
      ["salary", "Salary", "integer", "custom"],
      ["legacy", "Legacy", "text", "custom"],
    ]);
    expect(form.fields[3]?.sensitive).toBe(true);
  });

  it("validates with the schema and splits the input from the custom values", async () => {
    const form = recordForm(workItemInputSchema, {
      fields: ["title", "priority", "dueAt"],
      customFields: [
        { key: "region", label: "Region", type: "option", required: true },
      ],
      timeZone: "Europe/Amsterdam",
    });

    const result = await form.validate({
      title: "  Ship it ",
      priority: "2",
      dueAt: "2026-10-22T10:00",
      region: "eu",
      ignored: "x",
    });

    const values = valuesOf(result);

    expect(values.input.title).toBe("Ship it");
    expect(values.input.priority).toBe(2);
    expect(values.input.dueAt?.toString()).toBe("2026-10-22T08:00:00Z");
    expect(values.custom).toEqual({ region: "eu" });

    const zoned = await form.validate({
      title: "a",
      dueAt: "2026-10-22T10:00:00Z",
      region: "eu",
    });

    expect(zoned.ok && zoned.input.dueAt?.toString()).toBe(
      "2026-10-22T10:00:00Z",
    );
  });

  it("reports schema issues and missing required custom fields by key", async () => {
    const form = recordForm(workItemInputSchema, {
      fields: ["title", "priority"],
      customFields: [
        { key: "region", label: "Region", type: "option", required: true },
      ],
    });

    const result = await form.validate({
      title: "",
      priority: "nine",
      region: [],
    });

    expect(result).toEqual({
      ok: false,
      errors: {
        region: "Region is required",
        title: expect.any(String),
        priority: expect.any(String),
      },
    });
  });

  it("turns input text into each kind's value and keeps text that doesn't parse", async () => {
    const form = recordForm(everything);

    const result = await form.validate({
      id: "00000000-0000-4000-8000-000000000001",
      name: "x",
      count: "3",
      amount: "12",
      ratio: "0.5",
      active: "on",
      day: "2026-10-22",
      stamp: "2026-10-22T10:00:00Z",
      at: "2026-10-22T10:00:00+02:00",
      on: "2026-10-22",
      local: "2026-10-22T10:00",
      status: "open",
      tags: ["a"],
      data: '{"a":1}',
      extra: "kept",
      whatever: "kept",
    });

    const values = valuesOf(result);

    expect(values.input.amount).toBe(12n);
    expect(values.input.active).toBe(true);
    expect(values.input.at?.toString()).toBe("2026-10-22T08:00:00Z");
    expect(values.input.on?.toString()).toBe("2026-10-22");
    expect(values.input.local?.toString()).toBe("2026-10-22T10:00:00");
    expect(values.input.data).toEqual({ a: 1 });

    const bad = await form.validate({
      id: "00000000-0000-4000-8000-000000000001",
      name: "x",
      count: "many",
      amount: "1.5",
      active: "false",
      at: "not a date",
      data: "{",
    });

    expect(bad.ok).toBe(false);
    expect(!bad.ok && Object.keys(bad.errors).toSorted()).toEqual([
      "amount",
      "at",
      "count",
    ]);
  });

  it("keeps temporal text as text when no Temporal is available", async () => {
    const original = globalThis.Temporal;
    const provided = providedTemporal();
    provideTemporal(undefined);
    // SAFETY: the test removes the global for one call and restores it below.
    (globalThis as { Temporal?: unknown }).Temporal = undefined;

    const form = recordForm(everything, {
      fields: ["id", "name", "at", "on", "local"],
    });

    const result = await form.validate({
      id: "00000000-0000-4000-8000-000000000001",
      name: "x",
      at: "2026-10-22T10:00:00Z",
      on: "2026-10-22",
      local: "2026-10-22T10:00",
    });

    (globalThis as { Temporal?: unknown }).Temporal = original;
    provideTemporal(provided);

    expect(!result.ok && Object.keys(result.errors).toSorted()).toEqual([
      "at",
      "local",
      "on",
    ]);
  });

  it("reports an issue with no field under the empty key", async () => {
    const strict = {
      ...everything,
      "~standard": {
        ...everything["~standard"],
        validate: () => ({ issues: [{ message: "Too many fields" }] }),
      },
    } as typeof everything;

    const result = await recordForm(strict).validate({});

    expect(result).toEqual({ ok: false, errors: { "": "Too many fields" } });
  });
});
