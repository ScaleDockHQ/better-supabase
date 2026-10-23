import { describe, expect, it } from "vitest";

import type { ConfigEdit } from "../../../src/cli/sql/config-edit.ts";

import {
  currentOperationName,
  renameBlocksInConfig,
  renameBlocksInSource,
  withBlockNames,
} from "../../../src/cli/sql/config-block-names.ts";

const textOf = (edit: ConfigEdit): string =>
  edit.ok ? edit.text : edit.reason;

describe("currentOperationName", () => {
  it("renames the block part of an operation", () => {
    expect(currentOperationName("work-items.create")).toBe("tasks.create");
    expect(currentOperationName("comments.create")).toBe("comments.create");
    expect(currentOperationName("tenant")).toBe("tenant");
  });
});

describe("renameBlocksInSource", () => {
  it("renames block keys and keeps comments", () => {
    const source = `export default defineConfig({
  blocks: {
    // who changed a row
    actor: {},
    "work-items": { options: {} },
    comments: {},
  },
});
`;

    const next = textOf(renameBlocksInSource(source));

    expect(next).toContain("// who changed a row");
    expect(next).toContain('"created-by": {}');
    expect(next).toContain('"tasks": { options: {} }');
    expect(next).toContain("comments: {}");
  });

  it("renames the entries of a blocks list and the preset blocks", () => {
    const source = `export default defineConfig({
  blocks: ["tenant", "comments"],
  preset: { blocks: ["jobs"] },
});
`;

    const next = textOf(renameBlocksInSource(source));

    expect(next).toContain('blocks: ["memberships", "comments"]');
    expect(next).toContain('blocks: ["queue"]');
  });

  it("renames operations and the blocks in environment overrides", () => {
    const source = `export default defineConfig({
  auth: {
    authorization: { operations: { "work-items.create": "tasks.write" } },
  },
  $env: { staging: { blocks: { actor: {} } }, other: "x" },
  $production: { blocks: { jobs: {} } },
  $test: "skip",
  preset: { blocks: "all" },
});
`;

    const next = textOf(renameBlocksInSource(source));

    expect(next).toContain('{ "tasks.create": "tasks.write" }');
    expect(next).toContain('blocks: { "created-by": {} }');
    expect(next).toContain("blocks: { queue: {} }");
    expect(next).toContain('preset: { blocks: "all" }');
  });

  it("skips spreads, auth without operations and a bare preset", () => {
    const source = `export default defineConfig({
  ...base,
  auth: { authorization: "provider" },
  preset: "saas",
  blocks: { ...shared, tenant: {}, [key]: {} },
});
`;

    const next = textOf(renameBlocksInSource(source));

    expect(next).toContain('auth: { authorization: "provider" }');
    expect(next).toContain('preset: "saas"');
    expect(next).toContain("...shared, memberships: {}, [key]: {}");
  });

  it("reports a file without a config object", () => {
    expect(renameBlocksInSource("export const x = 1;\n")).toEqual({
      ok: false,
      reason: "no defineConfig({...}) or default export object found",
    });
  });

  it("leaves a config without renamed blocks alone", () => {
    const source = `export default defineConfig({ blocks: { comments: {} } });\n`;

    expect(textOf(renameBlocksInSource(source))).toBe(source);
  });
});

describe("renameBlocksInConfig", () => {
  it("renames keys, operations and environment overrides", () => {
    expect(
      renameBlocksInConfig({
        blocks: { access: {}, comments: {} },
        auth: { authorization: { operations: { "work-items.create": "x" } } },
        $test: { blocks: { actor: {} } },
      }),
    ).toEqual({
      blocks: { permissions: {}, comments: {} },
      auth: { authorization: { operations: { "tasks.create": "x" } } },
      $test: { blocks: { "created-by": {} } },
    });
  });

  it("renames lists and environments, and keeps other values", () => {
    expect(
      renameBlocksInConfig({
        blocks: ["tenant", 3],
        preset: { blocks: ["jobs"], casing: "camel" },
        $env: { staging: { blocks: { rules: {} } }, other: "x" },
        auth: { authorization: { provider: "x" } },
        name: "app",
      }),
    ).toEqual({
      blocks: ["memberships", 3],
      preset: { blocks: ["queue"], casing: "camel" },
      $env: { staging: { blocks: { automations: {} } }, other: "x" },
      auth: { authorization: { provider: "x" } },
      name: "app",
    });
    expect(
      renameBlocksInConfig({
        preset: { casing: "camel" },
        auth: { authorization: "x" },
      }),
    ).toEqual({ preset: { casing: "camel" }, auth: { authorization: "x" } });
  });
});

describe("withBlockNames", () => {
  const ok = (text: string): ConfigEdit => ({ ok: true, text });

  it("passes a failed edit through", () => {
    const failed: ConfigEdit = { ok: false, reason: "nope" };

    expect(withBlockNames(failed, true)).toBe(failed);
  });

  it("renames a JSON config and keeps an unchanged one", () => {
    expect(textOf(withBlockNames(ok('{"blocks":{"jobs":{}}}'), true))).toBe(
      '{\n  "blocks": {\n    "queue": {}\n  }\n}\n',
    );

    const same = ok('{"blocks":{"comments":{}}}');

    expect(withBlockNames(same, true)).toBe(same);
    expect(withBlockNames(ok("[]"), true)).toEqual(ok("[]"));
  });

  it("renames a TypeScript config", () => {
    expect(
      textOf(
        withBlockNames(
          ok("export default defineConfig({ blocks: { actor: {} } });\n"),
          false,
        ),
      ),
    ).toContain('"created-by": {}');
  });
});
