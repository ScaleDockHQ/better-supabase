import { describe, expect, it } from "vitest";

import {
  renameArguments,
  renameBlockReferences,
} from "../../src/cli/codemod-arguments.ts";

const argument = {
  kind: "argument",
  from: "workItemId",
  to: "taskId",
  since: "0.58",
} as const;

const block = {
  kind: "configKey",
  from: "blocks.time-tracking",
  to: "blocks.time-entries",
  since: "0.58",
} as const;

describe("renameArguments", () => {
  it("renames keys, members, shorthand and destructuring", () => {
    const { text } = renameArguments(
      [
        'import { workItemId } from "./ids.ts";',
        "export { workItemId };",
        "const a = { workItemId: id };",
        "const b = { workItemId };",
        "const c = result.workItemId + result?.workItemId;",
        'const d = result["workItemId"];',
        "const { workItemId, other: x } = args;",
        "const { workItemId: local } = args;",
        "type T = { workItemId: string };",
        "",
      ].join("\n"),
      [argument],
    );

    expect(text).toBe(
      [
        'import { workItemId } from "./ids.ts";',
        "export { workItemId };",
        "const a = { taskId: id };",
        "const b = { taskId: workItemId };",
        "const c = result.taskId + result?.taskId;",
        'const d = result["taskId"];',
        "const { taskId: workItemId, other: x } = args;",
        "const { taskId: local } = args;",
        "type T = { taskId: string };",
        "",
      ].join("\n"),
    );
  });

  it("collapses a key whose value is the new name", () => {
    expect(
      renameArguments("f({ workItemId: taskId, workItemId: other });", [
        argument,
      ]).text,
    ).toBe("f({ taskId, taskId: other });");
  });

  it("leaves comments, strings, template text and spreads alone", () => {
    const source = [
      "// { workItemId: 1 } and a.workItemId",
      'const s = "{ workItemId: 1 }";',
      "const t = `{ workItemId: 1 }`;",
      "const u = { ...workItemId, ...rest };",
      "/* result.workItemId */",
      "",
    ].join("\n");

    const result = renameArguments(source, [argument]);

    expect(result.text).toBe(source);
    expect(result.review).toEqual([]);
  });

  it("renames inside a template expression and next to a regex", () => {
    const hole = (name: string): string => `\`\${a.${name}}\``;

    expect(
      renameArguments(`const s = ${hole("workItemId")}; const r = /'/;`, [
        argument,
      ]).text,
    ).toBe(`const s = ${hole("taskId")}; const r = /'/;`);
  });

  it("keeps CRLF line endings", () => {
    const { text } = renameArguments(
      "const a = {\r\n  workItemId: 1,\r\n};\r\nx.workItemId;\r\n",
      [argument],
    );

    expect(text).toBe("const a = {\r\n  taskId: 1,\r\n};\r\nx.taskId;\r\n");
  });

  it("lists a file it cannot read instead of skipping it", () => {
    const source = "const a = { workItemId: ;\n";
    const result = renameArguments(source, [argument]);

    expect(result.text).toBe(source);
    expect(result.review).toEqual([
      expect.objectContaining({
        line: 1,
        message: expect.stringContaining("does not parse"),
      }),
    ]);
  });
});

describe("renameBlockReferences", () => {
  it("renames the key reads, the wiring key and $blocks members", () => {
    const { text } = renameBlockReferences(
      [
        'const a = config.blocks["time-tracking"];',
        "const b = blockConfig['time-tracking'];",
        "const c = db.$blocks.timeTracking.list();",
        'defineBlocks(blockConfig, { "time-tracking": blocks["time-tracking"].with({}) });',
        'const d = { "time-tracking": other["time-tracking"] };',
        '// blocks["time-tracking"] stays',
        'const e = "blocks[\\"time-tracking\\"]";',
        "",
      ].join("\r\n"),
      [block],
    );

    expect(text).toBe(
      [
        'const a = config.blocks["time-entries"];',
        "const b = blockConfig['time-entries'];",
        "const c = db.$blocks.timeEntries.list();",
        'defineBlocks(blockConfig, { "time-entries": blocks["time-entries"].with({}) });',
        'const d = { "time-tracking": other["time-tracking"] };',
        '// blocks["time-tracking"] stays',
        'const e = "blocks[\\"time-tracking\\"]";',
        "",
      ].join("\r\n"),
    );
  });

  it("lists a file that does not parse", () => {
    expect(
      renameBlockReferences("blocks[;", [block]).review[0]?.message,
    ).toContain("does not parse");
  });
});
