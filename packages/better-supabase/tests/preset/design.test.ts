import { describe, expect, it } from "vitest";

import {
  type CreateDesign,
  decodeDesign,
  designApplyCommand,
  designConfig,
  designConfigSource,
  designInstallCommand,
  designOf,
  encodeDesign,
  encodePreset,
  isDesignCode,
  isPresetCode,
  MAX_DESIGN_CODE_LENGTH,
  namedPreset,
  presetInstallCommand,
  presetOf,
  resolvePreset,
} from "../../src/preset/index.ts";

const DESIGN: CreateDesign = {
  appTables: {
    projects: {
      columns: {
        name: { type: "text", nullable: false },
        budget_minor: { type: "bigint", nullable: false, default: "0" },
      },
    },
    tasks: {
      columns: {
        project_id: {
          type: "uuid",
          nullable: false,
          references: { table: "projects", onDelete: "cascade" },
        },
      },
    },
  },
  extraColumns: { tags: { color: "text not null default 'gray'" } },
  positions: {
    "public.projects": [120, -40.5],
    "better_supabase.tags": [0, 0],
  },
};

const crm = resolvePreset(namedPreset("crm"));
const CREATE = `https://bettersupabase.com/create?preset=${encodePreset(crm.preset)}`;

async function deflated(text: string): Promise<string> {
  const bytes = new Uint8Array(
    await new Response(
      new Blob([text])
        .stream()
        .pipeThrough(new CompressionStream("deflate-raw")),
    ).arrayBuffer(),
  );

  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCodePoint(byte);
  }

  return `0${btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "")}`;
}

describe("design codes", () => {
  it("round-trips a design", async () => {
    const code = await encodeDesign(DESIGN);

    expect(isDesignCode(code)).toBe(true);
    expect(isPresetCode(code)).toBe(false);
    expect(await decodeDesign(code)).toEqual(DESIGN);
  });

  it("encodes an empty design to an empty code", async () => {
    expect(await encodeDesign({})).toBe("");
    expect(
      await encodeDesign({
        appTables: {},
        extraColumns: { tags: {} },
        positions: {},
      }),
    ).toBe("");
    expect(await decodeDesign("")).toEqual({});
  });

  it("drops empty parts", async () => {
    expect(
      await decodeDesign(
        await encodeDesign({ appTables: { notes: {} }, positions: {} }),
      ),
    ).toEqual({ appTables: { notes: {} } });
  });

  it("keeps preset names and codes apart from design codes", () => {
    expect(isDesignCode("crm")).toBe(false);
    expect(isDesignCode("ai")).toBe(false);
    expect(isDesignCode("1Abc")).toBe(false);
    expect(isDesignCode("0abc-_")).toBe(true);
    expect(isDesignCode(`0${"a".repeat(MAX_DESIGN_CODE_LENGTH)}`)).toBe(false);
  });

  it("rejects a code that isn't one", async () => {
    await expect(decodeDesign("crm")).rejects.toThrow(
      'design: "crm" is not a design code',
    );
    await expect(decodeDesign("0!!")).rejects.toThrow("is not a design code");
    await expect(decodeDesign("0abcd")).rejects.toThrow(
      "design: the code is damaged; copy it again from /create",
    );
    await expect(
      decodeDesign(`0${"a".repeat(MAX_DESIGN_CODE_LENGTH)}`),
    ).rejects.toThrow(
      `design: the code is longer than ${String(MAX_DESIGN_CODE_LENGTH)} characters`,
    );
  });

  it("rejects a code that inflates past the cap", async () => {
    await expect(
      decodeDesign(await deflated(" ".repeat(300_000))),
    ).rejects.toThrow("design: the code inflates past 262144 bytes");
  });

  it("rejects JSON that isn't a design", async () => {
    await expect(decodeDesign(await deflated("[1]"))).rejects.toThrow(
      "design must be an object",
    );
    await expect(
      decodeDesign(await deflated(JSON.stringify({ tables: {} }))),
    ).rejects.toThrow(
      'design: unknown key "tables"; a design has appTables, extraColumns and positions',
    );
  });

  it("checks app tables like the config does", async () => {
    await expect(encodeDesign({ appTables: { Projects: {} } })).rejects.toThrow(
      "appTables",
    );
  });

  it("checks extra columns against the catalog", async () => {
    await expect(
      encodeDesign({ extraColumns: { nope: { a: "text" } } }),
    ).rejects.toThrow('design.extraColumns.nope: "nope" is not a block');
    await expect(
      encodeDesign({ extraColumns: { "updated-at": { a: "text" } } }),
    ).rejects.toThrow(
      "design.extraColumns.updated-at: the updated-at block takes no extra columns",
    );
    await expect(
      encodeDesign({ extraColumns: { tags: { Color: "text" } } }),
    ).rejects.toThrow(
      'design.extraColumns.tags: "Color" is not a valid column name',
    );
    await expect(
      encodeDesign({ extraColumns: { tags: { color: "text; drop table x" } } }),
    ).rejects.toThrow("design.extraColumns.tags.color must be a SQL type");
    await expect(
      encodeDesign({ extraColumns: { tags: { color: "text -- x" } } }),
    ).rejects.toThrow("design.extraColumns.tags.color must be a SQL type");
  });

  it("checks positions", async () => {
    await expect(
      encodeDesign({ positions: { projects: [0, 0] } }),
    ).rejects.toThrow(
      'design.positions: "projects" is not a schema.table name',
    );
    await expect(
      encodeDesign({ positions: { "public.projects": [0, Number.NaN] } }),
    ).rejects.toThrow(
      "design.positions.public.projects must be [x, y], two finite numbers",
    );
    await expect(
      decodeDesign(
        await deflated(
          JSON.stringify({ positions: { "public.p": [1, 2, 3] } }),
        ),
      ),
    ).rejects.toThrow("must be [x, y]");
  });

  it("refuses parts of the wrong shape and past their caps", async () => {
    const decoded = async (value: unknown): Promise<CreateDesign> =>
      decodeDesign(await deflated(JSON.stringify(value)));

    const many = (count: number, entry: (index: number) => unknown) =>
      Object.fromEntries(
        Array.from({ length: count }, (_, index) => [
          `t_${String(index)}`,
          entry(index),
        ]),
      );

    await expect(decoded({ extraColumns: [] })).rejects.toThrow(
      "design.extraColumns must be an object",
    );
    await expect(decoded({ extraColumns: { tags: "text" } })).rejects.toThrow(
      "design.extraColumns.tags",
    );
    await expect(
      decoded({ extraColumns: { tags: many(65, () => "text") } }),
    ).rejects.toThrow("design.extraColumns.tags");
    await expect(decoded({ positions: [] })).rejects.toThrow(
      "design.positions must be an object",
    );
    await expect(
      decoded({ positions: many(1001, () => [0, 0]) }),
    ).rejects.toThrow("design.positions");
    await expect(decoded({ appTables: many(101, () => ({})) })).rejects.toThrow(
      "design.appTables",
    );
  });

  it("refuses a design too large for a URL", async () => {
    const appTables = Object.fromEntries(
      Array.from({ length: 100 }, (_, index) => [
        `table_${String(index)}_${crypto.randomUUID().replaceAll("-", "_")}`,
        {
          columns: Object.fromEntries(
            Array.from({ length: 6 }, (__, column) => [
              `c${String(column)}_${crypto.randomUUID().replaceAll("-", "").slice(0, 20)}`,
              { type: "text" as const },
            ]),
          ),
        },
      ]),
    );

    await expect(encodeDesign({ appTables })).rejects.toThrow(
      "Download the config instead, save it as better-supabase.config.ts, then run `better-supabase init` and `better-supabase sql sync`.",
    );
  });
});

describe("designOf", () => {
  it("reads the design of a /create URL", async () => {
    const code = await encodeDesign(DESIGN);
    const url = `https://bettersupabase.com/create?preset=crm&design=${code}`;

    expect(await designOf(url)).toEqual(DESIGN);
    expect(await designOf(code)).toEqual(DESIGN);
    expect(presetOf(url)).toEqual(namedPreset("crm"));
  });

  it("reads nothing from a URL or string without a design", async () => {
    expect(await designOf("https://bettersupabase.com/create?preset=crm")).toBe(
      undefined,
    );
    expect(await designOf("crm")).toBe(undefined);
    expect(
      await designOf("https://bettersupabase.com/create?preset=crm&design="),
    ).toEqual({});
  });
});

describe("design config", () => {
  it("merges extra columns into the blocks and adds appTables", () => {
    const config = designConfig(crm, DESIGN);

    expect(config.blocks["tags"]).toEqual({
      options: { extraColumns: { color: "text not null default 'gray'" } },
    });
    expect(Object.keys(config.appTables ?? {})).toEqual(["projects", "tasks"]);
    expect(config).not.toHaveProperty("positions");
  });

  it("refuses extra columns on a block the preset doesn't install", () => {
    expect(() =>
      designConfig(resolvePreset(namedPreset("minimal")), {
        extraColumns: { tags: { color: "text" } },
      }),
    ).toThrow(
      "design.extraColumns.tags: the preset doesn't install the tags block",
    );
  });

  it("writes the config source with the design URL", async () => {
    const code = await encodeDesign(DESIGN);
    const source = designConfigSource(crm, DESIGN, code);

    expect(source).toContain(`// ${CREATE}&design=${code}`);
    expect(source).toContain(
      `    tags: { options: { extraColumns: { color: "text not null default 'gray'" } } },`,
    );
    expect(source).toContain("  appTables: {\n    projects: { columns: {");
    expect(source).not.toContain("positions");
  });

  it("quotes the URL in the commands", async () => {
    const code = await encodeDesign(DESIGN);

    expect(designInstallCommand(crm, code)).toBe(
      `npx better-supabase init --preset "${CREATE}&design=${code}"`,
    );
    expect(designApplyCommand(crm, code)).toBe(
      `npx better-supabase apply --preset "${CREATE}&design=${code}"`,
    );
    expect(designInstallCommand(crm, "")).toBe(presetInstallCommand(crm));
  });
});
