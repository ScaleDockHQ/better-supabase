import {
  decodePreset,
  encodePreset,
  namedPreset,
  type Preset,
  PRESET_NAMES,
  presetApplyCommand,
  presetInstallCommand,
  resolvePreset,
} from "better-supabase/preset";
import { describe, expect, test } from "vitest";

import { blocks } from "../../lib/blocks";
import {
  applyNamedPreset,
  blockGroups,
  commandFor,
  CONFIG_FILE,
  createHref,
  DEFAULT_PRESET,
  initialPreset,
  matchingPreset,
  PACKAGE_MANAGERS,
  packageDir,
  packagePath,
  presetColumns,
  rowNote,
  shuffledPreset,
  toggleBlock,
  withPackage,
} from "../../lib/create";

const minimal = namedPreset("minimal");

function rowOf(preset: Preset, name: string) {
  return blockGroups(preset, resolvePreset(preset))
    .flatMap((group) => group.rows)
    .find((row) => row.name === name);
}

describe("the /create URL", () => {
  test("starts from a name, a code or the default", () => {
    expect(initialPreset(null)).toEqual(namedPreset(DEFAULT_PRESET));
    expect(initialPreset("")).toEqual(namedPreset(DEFAULT_PRESET));
    expect(initialPreset("minimal")).toEqual(minimal);
    expect(initialPreset("not a preset")).toEqual(namedPreset(DEFAULT_PRESET));
    const code = createHref(minimal).split("=")[1] ?? "";
    expect(initialPreset(code)).toEqual(minimal);
  });

  test("keeps the selection as a code that decodes to it", () => {
    const preset = toggleBlock(minimal, "comments");
    const code = createHref(preset).replace("/create?preset=", "");
    expect(decodePreset(code).preset.blocks.toSorted()).toEqual([
      "comments",
      "profiles",
    ]);
  });

  test("keeps the monorepo package outside the preset code", () => {
    const code = encodePreset(minimal);
    expect(createHref(minimal, "apps/web")).toBe(
      `/create?preset=${code}&package=apps/web`,
    );
    expect(createHref(minimal, "packages/my app")).toBe(
      `/create?preset=${code}&package=packages/my%20app`,
    );
    expect(createHref(minimal)).toBe(`/create?preset=${code}`);
  });

  test("keeps the authorization library only with the provider access model", () => {
    const provider: Preset = { ...minimal, access: "provider" };
    const code = encodePreset(provider);
    expect(createHref(provider, "apps/web", "lib")).toBe(
      `/create?preset=${code}&authz=lib&package=apps/web`,
    );
    expect(createHref(minimal, undefined, "lib")).toBe(
      `/create?preset=${encodePreset(minimal)}`,
    );
  });
});

describe("the monorepo package", () => {
  test("accepts a relative path inside the repository", () => {
    expect(packageDir("apps/web")).toBe("apps/web");
    expect(packageDir("./apps/web/")).toBe("apps/web");
    expect(packageDir("packages/@scope/app")).toBe("packages/@scope/app");
  });

  test("rejects absolute paths, parent segments and empty values", () => {
    const accepted = [
      null,
      "",
      ".",
      "/apps/web",
      "../web",
      "apps/../web",
      "apps//web",
      String.raw`apps\web`,
      "C:/web",
    ].filter((value) => packageDir(value) !== undefined);

    expect(accepted).toEqual([]);
  });

  test("adds --package to init and --config to apply", () => {
    const resolved = resolvePreset(minimal);
    const code = encodePreset(minimal);
    expect(withPackage(presetInstallCommand(resolved), "apps/web")).toBe(
      `npx better-supabase init --preset ${code} --package apps/web`,
    );
    expect(withPackage(presetApplyCommand(resolved), "apps/web")).toBe(
      `npx better-supabase apply --preset ${code} --config apps/web/better-supabase.config.ts`,
    );
    expect(withPackage(presetInstallCommand(resolved), undefined)).toBe(
      presetInstallCommand(resolved),
    );
  });

  test("prefixes the package's files", () => {
    expect(packagePath("lib/blocks.ts", "apps/web")).toBe(
      "apps/web/lib/blocks.ts",
    );
    expect(packagePath(CONFIG_FILE, undefined)).toBe(
      "better-supabase.config.ts",
    );
  });
});

describe("the package manager switch", () => {
  test("runs the command through each manager's runner", () => {
    const command = "npx better-supabase init --preset 1A";
    expect(PACKAGE_MANAGERS.map((each) => commandFor(command, each))).toEqual([
      "pnpm dlx better-supabase init --preset 1A",
      "npx better-supabase init --preset 1A",
      "yarn dlx better-supabase init --preset 1A",
      "bunx better-supabase init --preset 1A",
    ]);
  });
});

describe("shuffledPreset", () => {
  test("picks a named preset other than the current one", () => {
    for (const random of [0, 0.5, 0.99]) {
      const name = shuffledPreset("saas", () => random);
      expect(PRESET_NAMES).toContain(name);
      expect(name).not.toBe("saas");
    }

    expect(shuffledPreset(undefined, () => 0)).toBe(PRESET_NAMES[0]);
  });
});

describe("selection helpers", () => {
  test("toggle a block on and off", () => {
    const on = toggleBlock(minimal, "tags");
    expect(on.blocks).toEqual(["profiles", "tags"]);
    expect(toggleBlock(on, "tags").blocks).toEqual(["profiles"]);
  });

  test("name the preset a selection matches", () => {
    expect(matchingPreset(minimal)).toBe("minimal");
    expect(matchingPreset(toggleBlock(minimal, "tags"))).toBeUndefined();
    const crm = applyNamedPreset({ ...minimal, casing: "camel" }, "crm");
    expect(matchingPreset(crm)).toBe("crm");
    expect(crm.casing).toBe("camel");
  });
});

describe("blockGroups", () => {
  test("lists every catalog block once, in the /blocks categories", () => {
    const names = blockGroups(minimal, resolvePreset(minimal)).flatMap(
      (group) => group.rows.map((row) => row.name),
    );

    expect(names.toSorted()).toEqual(
      blocks.map((block) => block.name).toSorted(),
    );
  });

  test("switches on what a selected block requires, with the reason", () => {
    const preset = toggleBlock(minimal, "comments");
    expect(rowOf(preset, "comments")?.state).toEqual({ kind: "selected" });
    const tenant = rowOf(preset, "tenant");
    expect(tenant?.state).toEqual({
      kind: "required",
      by: ["access", "comments"],
    });
    expect(
      rowNote(rowOf(preset, "access")?.state ?? { kind: "selected" }),
    ).toBe("Required by comments");
  });

  test("disables a block that can't install, with the reason", () => {
    const preset: Preset = { ...minimal, scope: "user" };
    const state = rowOf(preset, "organizations")?.state;
    expect(state).toEqual({
      kind: "conflict",
      reason: 'it needs tenants, and scope "user" has none',
    });
    expect(rowNote(state ?? { kind: "selected" })).toBe(
      'Unavailable: it needs tenants, and scope "user" has none',
    );
  });

  test("says which installed blocks an available block works with", () => {
    const preset = toggleBlock(minimal, "comments");
    const state = rowOf(preset, "notifications")?.state;
    expect(state?.kind).toBe("available");
    expect(rowNote(state ?? { kind: "selected" })).toContain("comments");
    expect(rowNote({ kind: "available", worksWith: [] })).toBeUndefined();
    expect(rowNote({ kind: "selected" })).toBeUndefined();
  });
});

describe("presetColumns", () => {
  test("puts every block right of what it requires", () => {
    const { columns, edges } = presetColumns(
      resolvePreset(toggleBlock(minimal, "comments")),
    );

    const column = new Map(
      columns.flatMap((nodes, index) =>
        nodes.map((node) => [node.name, index] as const),
      ),
    );

    for (const edge of edges.filter((each) => each.kind === "requires")) {
      expect(column.get(edge.from)).toBeGreaterThan(
        column.get(edge.to) ?? Infinity,
      );
    }

    expect(edges).toContainEqual({
      from: "comments",
      to: "access",
      kind: "requires",
    });
    expect(columns.length).toBeGreaterThanOrEqual(2);
    expect(
      columns.flat().find((node) => node.name === "comments")?.selected,
    ).toBe(true);
  });

  test("is empty without blocks", () => {
    const { columns, edges } = presetColumns(
      resolvePreset({ ...minimal, blocks: [] }),
    );

    expect(columns).toEqual([]);
    expect(edges).toEqual([]);
  });
});
