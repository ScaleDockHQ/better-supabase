import { describe, expect, it } from "vitest";

import type { CreateDesign } from "../../src/preset/index.ts";

import {
  decodeDesign,
  DESIGN_FORMAT,
  designApplyCommand,
  designFormat,
  designConfig,
  designConfigSource,
  designInstallCommand,
  designOf,
  DesignTooLongError,
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
const CREATE = `https://app.bettersupabase.com/create?preset=${encodePreset(crm.preset)}`;

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

  return `0${btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/[=]+$/, "")}`;
}

describe("design codes", () => {
  it("round-trips a design", async () => {
    const code = await encodeDesign(DESIGN);

    expect(isDesignCode(code)).toBe(true);
    expect(isPresetCode(code)).toBe(false);
    expect(await decodeDesign(code)).toEqual(DESIGN);
  });

  it("writes format 1 only for a design that needs it", async () => {
    const formatted: CreateDesign = {
      appTables: {
        contacts: {
          id: "bigint",
          unique: [["email"]],
          columns: {
            email: { type: "text", format: "email" },
            stage: { type: "text", options: ["lead", "won"] },
          },
        },
      },
    };

    expect(designFormat(DESIGN)).toBe(0);
    expect(designFormat(formatted)).toBe(1);
    expect(await decodeDesign(await encodeDesign(formatted))).toEqual(
      formatted,
    );
    expect(await decodeDesign(await deflated(JSON.stringify(DESIGN)))).toEqual(
      DESIGN,
    );
    expect(
      await decodeDesign(
        await deflated(JSON.stringify({ version: 1, ...formatted })),
      ),
    ).toEqual(formatted);
    await expect(
      decodeDesign(await deflated(JSON.stringify({ version: 9 }))),
    ).rejects.toThrow(
      "design: the code needs format 9, and this better-supabase reads up to 6; update better-supabase",
    );
  });

  it("writes format 2 for a table that is a subject", async () => {
    const subject: CreateDesign = {
      appTables: {
        projects: {
          columns: { name: { type: "text" } },
          subject: { type: "project", title: "name", rank: true },
        },
      },
    };

    expect(designFormat(subject)).toBe(2);
    expect(await decodeDesign(await encodeDesign(subject))).toEqual(subject);
  });

  it("writes format 3 for rollups and lookups", async () => {
    const computed: CreateDesign = {
      appTables: {
        projects: {
          columns: { name: { type: "text" } },
          rollups: {
            task_count: {
              table: "tasks",
              via: "project_id",
              aggregate: "count",
            },
          },
        },
        tasks: {
          columns: {
            project_id: { type: "uuid", references: { table: "projects" } },
          },
          lookups: { project_name: { via: "project_id", column: "name" } },
        },
      },
    };

    expect(designFormat(computed)).toBe(3);
    expect(await decodeDesign(await encodeDesign(computed))).toEqual(computed);
    await expect(
      encodeDesign({
        appTables: {
          projects: {
            rollups: {
              n: { table: "tasks", via: "project_id", aggregate: "count" },
            },
          },
        },
      }),
    ).rejects.toThrow("rollups.n.table must name an app table");
  });

  it("writes format 4 for table events", async () => {
    const events: CreateDesign = {
      appTables: {
        tasks: {
          columns: { status: { type: "text" } },
          events: { on: ["created"], include: ["status"] },
        },
      },
    };

    expect(designFormat(events)).toBe(4);
    expect(await decodeDesign(await encodeDesign(events))).toEqual(events);
  });

  it("writes format 4 for subject versions", async () => {
    const versions: CreateDesign = {
      appTables: {
        tasks: {
          columns: { status: { type: "text" } },
          subject: { type: "task", versions: { columns: ["status"] } },
        },
      },
    };

    expect(designFormat(versions)).toBe(4);
    expect(await decodeDesign(await encodeDesign(versions))).toEqual(versions);
  });

  it("writes format 5 for column access", async () => {
    const access: CreateDesign = {
      appTables: {
        projects: {
          columns: {
            name: { type: "text" },
            internal_notes: { type: "text", access: "server" },
          },
        },
      },
    };

    expect(designFormat(access)).toBe(5);
    expect(await decodeDesign(await encodeDesign(access))).toEqual(access);
  });

  it("writes format 6 for encrypted columns and read audits", async () => {
    const encrypted: CreateDesign = {
      appTables: {
        patients: { columns: { ssn: { type: "text", encrypted: true } } },
      },
    };

    const audited: CreateDesign = {
      appTables: {
        patients: {
          auditReads: true,
          columns: { ssn: { type: "text", encrypted: true } },
        },
      },
    };

    expect(designFormat(encrypted)).toBe(DESIGN_FORMAT);
    expect(designFormat(audited)).toBe(DESIGN_FORMAT);
    expect(await decodeDesign(await encodeDesign(audited))).toEqual(audited);
  });

  it("rejects an unknown column access", async () => {
    await expect(
      encodeDesign({
        appTables: {
          projects: {
            // SAFETY: an invalid value on purpose, as a hand-edited code carries it.
            columns: { notes: { type: "text", access: "owner" as "server" } },
          },
        },
      }),
    ).rejects.toThrow("access");
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

  it("throws DesignTooLongError only for a valid design that is too long", async () => {
    const columns = Object.fromEntries(
      Array.from({ length: 900 }, (_, index) => [
        `c${String(index * 7919)}_${String(index).padStart(4, "x")}`,
        { type: "text" as const },
      ]),
    );

    const long = await encodeDesign({ appTables: { wide: { columns } } }).then(
      () => undefined,
      (error: unknown) => error,
    );

    expect(long).toBeInstanceOf(DesignTooLongError);
    expect(long).toBeInstanceOf(TypeError);

    const invalid = await encodeDesign({
      appTables: { notes: { columns: { user_id: { type: "uuid" } } } },
    }).then(
      () => undefined,
      (error: unknown) => error,
    );

    expect(invalid).toBeInstanceOf(TypeError);
    expect(invalid).not.toBeInstanceOf(DesignTooLongError);
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
      "tables.Projects",
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
      "Download the design file instead, then run `better-supabase init --preset ./better-supabase.design.json`.",
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
    expect(
      await designOf("https://bettersupabase.com/create?preset=crm"),
    ).toBeUndefined();
    expect(await designOf("crm")).toBeUndefined();
    expect(
      await designOf("https://bettersupabase.com/create?preset=crm&design="),
    ).toEqual({});
  });
});

describe("design config", () => {
  it("merges extra columns into the blocks and adds appTables", () => {
    const config = designConfig(crm, DESIGN);

    expect(config.blocks.tags).toEqual({
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
    expect(source).toContain("  tables: {\n    projects: { columns: {");
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
