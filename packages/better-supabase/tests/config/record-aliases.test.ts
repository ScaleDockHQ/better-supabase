import { describe, expect, it } from "vitest";

import {
  recordTypeWires,
  withRecordTypeAliases,
} from "../../src/config/record-aliases.ts";

describe("record type aliases", () => {
  it("uses the alias as the wire name, else the key", () => {
    const wires = recordTypeWires({
      time_entry: { table: "time_entries", alias: "time-entry" },
      task: { table: "tasks" },
    });

    expect([...wires]).toEqual([
      ["time_entry", "time-entry"],
      ["task", "task"],
    ]);
  });

  it("rejects a bad alias and a duplicate wire name", () => {
    expect(() =>
      recordTypeWires({ a: { table: "a", alias: "Bad Name" } }),
    ).toThrow(/alias/);

    expect(() =>
      recordTypeWires({
        a: { table: "a", alias: "x" },
        b: { table: "b", alias: "x" },
      }),
    ).toThrow(/both resolve to the wire name "x"/);
  });

  it("renames the types and every block's on, leaving a config without aliases alone", () => {
    const plain = { recordTypes: { task: { table: "tasks" } }, blocks: {} };

    expect(withRecordTypeAliases(plain)).toBe(plain);

    const renamed = withRecordTypeAliases({
      recordTypes: { time_entry: { table: "t", alias: "time-entry" } },
      blocks: {
        tags: { on: ["time_entry"] },
        notes: { on: { time_entry: { column: "x" } } },
      },
    });

    expect(renamed.recordTypes).toEqual({ "time-entry": { table: "t" } });
    expect(renamed.blocks).toEqual({
      tags: { on: ["time-entry"] },
      notes: { on: { "time-entry": { column: "x" } } },
    });
  });
});
