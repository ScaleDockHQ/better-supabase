import { describe, expect, it } from "vitest";

import { addBlocksToWiring } from "../../../src/cli/sql/config-edit.ts";
import {
  removeBlocksFromConfig,
  removeBlocksFromJson,
  removeBlocksFromWiring,
} from "../../../src/cli/sql/remove-edit.ts";

const HEAD = 'import { defineConfig } from "better-supabase/config";\n\n';

describe("removeBlocksFromConfig", () => {
  it("cuts keys from a multiline blocks object, keeping comments elsewhere", () => {
    const source = `${HEAD}export default defineConfig({
  blocks: {
    // Tags label records.
    tags: true,
    comments: { options: { reactions: true } },
    audit: true,
  },
});
`;

    expect(removeBlocksFromConfig(source, ["comments", "audit"])).toEqual({
      ok: true,
      text: `${HEAD}export default defineConfig({
  blocks: {
    // Tags label records.
    tags: true,
  },
});
`,
    });
  });

  it("cuts keys from an inline object and items from a list", () => {
    expect(
      removeBlocksFromConfig(
        `${HEAD}export default defineConfig({ blocks: { tags: true, comments: true } });\n`,
        ["comments"],
      ),
    ).toEqual({
      ok: true,
      text: `${HEAD}export default defineConfig({ blocks: { tags: true } });\n`,
    });
    expect(
      removeBlocksFromConfig(
        `${HEAD}export default defineConfig({ blocks: ["tags", 'comments'] });\n`,
        ["comments"],
      ),
    ).toEqual({
      ok: true,
      text: `${HEAD}export default defineConfig({ blocks: ["tags"] });\n`,
    });
  });

  it("leaves a config without the blocks alone", () => {
    const list = `${HEAD}export default defineConfig({ blocks: ["tags"] });\n`;
    const none = `${HEAD}export default defineConfig({ auth: {} });\n`;

    expect(removeBlocksFromConfig(list, ["comments"])).toEqual({
      ok: true,
      text: list,
    });
    expect(removeBlocksFromConfig(none, ["comments"])).toEqual({
      ok: true,
      text: none,
    });
  });

  it("refuses a config it can't edit", () => {
    expect(
      removeBlocksFromConfig("export default makeConfig();\n", ["tags"]),
    ).toMatchObject({ ok: false, reason: expect.stringContaining("object") });
    expect(
      removeBlocksFromConfig(
        `${HEAD}export default defineConfig({ blocks: shared });\n`,
        ["tags"],
      ),
    ).toMatchObject({ ok: false, reason: expect.stringContaining("literal") });
  });
});

describe("removeBlocksFromJson", () => {
  it("takes names out of a list or an object, keeping the indent", () => {
    expect(
      removeBlocksFromJson('{\n    "blocks": ["tags", "comments"]\n}\n', [
        "comments",
      ]),
    ).toEqual({
      ok: true,
      text: '{\n    "blocks": [\n        "tags"\n    ]\n}\n',
    });
    expect(
      removeBlocksFromJson('{ "blocks": { "tags": true, "audit": {} } }', [
        "audit",
      ]),
    ).toEqual({
      ok: true,
      text: '{\n  "blocks": {\n    "tags": true\n  }\n}\n',
    });
  });

  it("leaves a file without the blocks alone and refuses one it can't read", () => {
    const source = '{ "blocks": ["tags"] }';

    expect(removeBlocksFromJson(source, ["audit"])).toEqual({
      ok: true,
      text: source,
    });
    expect(removeBlocksFromJson("{}", ["audit"])).toEqual({
      ok: true,
      text: "{}",
    });
    expect(removeBlocksFromJson("{", ["audit"])).toMatchObject({ ok: false });
    expect(removeBlocksFromJson("[]", ["audit"])).toMatchObject({ ok: false });
    expect(
      removeBlocksFromJson('{ "blocks": "tags" }', ["tags"]),
    ).toMatchObject({ ok: false });
  });
});

describe("removeBlocksFromWiring", () => {
  const comments = {
    key: "comments",
    export: "commentsBlock",
    subpath: "better-supabase/blocks/comments",
  };

  const source =
    'import { createBlocks } from "better-supabase/blocks";\n\nexport const blocks = createBlocks({ transport }, { tags: tagsBlock });\n';

  it("undoes addBlocksToWiring", () => {
    const added = addBlocksToWiring(source, [comments]);

    expect(added.ok && removeBlocksFromWiring(added.text, [comments])).toEqual({
      ok: true,
      text: source,
    });
  });

  it("keeps an import another line still names", () => {
    const shared = `import { commentsBlock } from "better-supabase/blocks/comments";\n\nexport const blocks = createBlocks({ transport }, { comments: commentsBlock });\nexport const extra = commentsBlock;\n`;

    const edit = removeBlocksFromWiring(shared, [comments]);

    expect(edit).toMatchObject({ ok: true });
    expect(edit.ok && edit.text).toContain("import { commentsBlock }");
    expect(edit.ok && edit.text).toContain("createBlocks({ transport }, {})");
  });

  it("refuses a file without a blocks object", () => {
    expect(
      removeBlocksFromWiring("export const blocks = 1;\n", [comments]),
    ).toMatchObject({ ok: false });
  });
});
