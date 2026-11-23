import { describe, expect, it } from "vitest";

import { recordTypes } from "../../src/cli/codemod-record-types.ts";

const config = (on: string): string => `export default {
  recordTypes: {
    time_entry: { table: "time_entries" },
    task: { table: "tasks", alias: "work-item" },
  },
  blocks: [{ block: "tags", on: ${on} }, "contacts"],
};
`;

describe("codemod record-types", () => {
  it("leaves a source file that is not a config alone, even one that is not valid TypeScript", () => {
    const jsx = 'export const View = () => <div className="a">x</div>;\n';

    expect(recordTypes(jsx).text).toBe(jsx);
  });

  it("writes a list entry as the registered name", () => {
    const { text } = recordTypes(config('["time-entry", "task"]'));

    expect(text).toContain('on: ["time_entry", "task"]');
  });

  it("renames an object key and an alias, and leaves the rest", () => {
    const { text } = recordTypes(
      config('{ "time-entry": { column: "x" }, "work-item": {} }'),
    );

    expect(text).toContain('{ "time_entry": { column: "x" }, "task": {} }');
    expect(text).toContain('table: "time_entries"');
    expect(text).toContain('alias: "work-item"');
  });

  it("changes nothing when the names already match", () => {
    const source = config('["time_entry"]');

    expect(recordTypes(source).text).toBe(source);
  });

  it("changes nothing without recordTypes", () => {
    const source =
      'export default { blocks: [{ block: "tags", on: ["a-b"] }] };';

    expect(recordTypes(source).text).toBe(source);
  });
});
