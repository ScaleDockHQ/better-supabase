import { describe, expect, it } from "vitest";

import type { ConfigEdit } from "../../../src/cli/sql/config-edit.ts";

import {
  movePluginsInJson,
  movePluginsInSource,
} from "../../../src/cli/sql/config-plugins.ts";

const textOf = (edit: ConfigEdit): string =>
  edit.ok ? edit.text : edit.reason;

describe("movePluginsInSource", () => {
  it("moves each plugin flag onto its block", () => {
    const source = `export default defineConfig({
  plugins: {
    timestamps: { updatedAt: "changed_at" },
    softDelete: { column: "archived_at" },
    actor: true,
  },
  blocks: ["comments"],
});
`;

    const next = textOf(movePluginsInSource(source));

    expect(next).not.toContain("plugins");
    expect(next).toContain("comments");
    expect(next).toMatch(/"updated-at": \{[^}]*updatedAt: "changed_at"/s);
    expect(next).toMatch(/trash: \{[^}]*deletedAt: "archived_at"/s);
    expect(next).toContain('"created-by"');
  });

  it("keeps a 0.14 tenant() failing closed on the organization column", () => {
    const next = textOf(
      movePluginsInSource(`export default defineConfig({
  plugins: { tenant: true },
});
`),
    );

    expect(next).not.toContain("plugins");
    expect(next).toContain('column: "organization_id"');
    expect(next).toContain('onMissing: "error"');
  });

  it("leaves a config without plugins alone", () => {
    const source = `export default defineConfig({ blocks: ["trash"] });\n`;

    expect(textOf(movePluginsInSource(source))).toBe(source);
    expect(textOf(movePluginsInSource("export const x = 1;\n"))).toBe(
      "export const x = 1;\n",
    );
  });

  it("keeps the organization column to memberships and an existing onMissing", () => {
    const next = textOf(
      movePluginsInSource(`export default defineConfig({
  plugins: { tenant: true, timestamps: false },
  blocks: { memberships: {} },
  auth: { tenant: { onMissing: "skip" } },
});
`),
    );

    expect(next).not.toContain("plugins");
    expect(next).not.toContain("organization_id");
    expect(next).not.toContain("updated-at");
    expect(next).toContain('onMissing: "skip"');
    expect(next).not.toContain('onMissing: "error"');
  });

  it.each([
    ["plugins: tenantPlugins", "its plugins key isn't a literal object"],
    ["plugins: { ...rest }", "plugins has a spread or a computed key"],
    [
      "plugins: { actor: enabled }",
      "plugins.actor isn't true, false or an object",
    ],
    [
      "plugins: { actor: { createdBy: column } }",
      "plugins.actor has a key that isn't a string",
    ],
    ["plugins: { audit: true }", "plugins.audit is not a plugin flag 0.14 had"],
    [
      'plugins: { actor: { ownerId: "owner_id" } }',
      "plugins.actor.ownerId is not a column it took",
    ],
  ])("refuses %s", (plugins, reason) => {
    expect(
      movePluginsInSource(
        `export default defineConfig({\n  ${plugins},\n});\n`,
      ),
    ).toEqual({ ok: false, reason });
  });
});

describe("movePluginsInJson", () => {
  it("moves the plugin flags of a JSON config", () => {
    const next = textOf(
      movePluginsInJson(
        `${JSON.stringify(
          {
            plugins: {
              timestamps: true,
              softDelete: { column: "archived_at" },
              tenant: true,
              actor: true,
            },
          },
          null,
          2,
        )}\n`,
      ),
    );

    const config = JSON.parse(next) as Record<string, unknown>;

    expect(config).not.toHaveProperty("plugins");
    expect(config).toMatchObject({
      auth: { tenant: { column: "organization_id", onMissing: "error" } },
      blocks: {
        "updated-at": {},
        "created-by": {},
        trash: { options: { deletedAt: "archived_at" } },
      },
    });
  });

  it("adds to a list of blocks and leaves the column to memberships", () => {
    const config = JSON.parse(
      textOf(
        movePluginsInJson(
          JSON.stringify({
            blocks: ["memberships"],
            plugins: { tenant: true, timestamps: { createdAt: "made_at" } },
          }),
        ),
      ),
    ) as Record<string, unknown>;

    expect(config).toEqual({
      blocks: {
        memberships: {},
        "updated-at": { options: { createdAt: "made_at" } },
      },
      auth: { tenant: { onMissing: "error" } },
    });
  });

  it("keeps the blocks key when only tenant moves", () => {
    const config = JSON.parse(
      textOf(
        movePluginsInJson(
          JSON.stringify({ blocks: ["comments"], plugins: { tenant: false } }),
        ),
      ),
    ) as Record<string, unknown>;

    expect(config).toEqual({ blocks: ["comments"] });
  });

  it("leaves invalid JSON and a config without plugins alone", () => {
    expect(textOf(movePluginsInJson("{"))).toBe("{");
    expect(textOf(movePluginsInJson("[]"))).toBe("[]");
  });

  it.each([
    [{ plugins: true }, "its plugins key isn't an object"],
    [{ plugins: { actor: 1 } }, "plugins.actor isn't true, false or columns"],
    [
      { plugins: { audit: true } },
      "plugins.audit is not a plugin flag 0.14 had",
    ],
  ])("refuses %j", (config, reason) => {
    expect(movePluginsInJson(JSON.stringify(config))).toEqual({
      ok: false,
      reason,
    });
  });
});
