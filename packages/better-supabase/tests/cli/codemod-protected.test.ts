import { describe, expect, it } from "vitest";

import {
  PROTECTED_OPTIONS,
  configCodemod,
} from "../../src/cli/codemod-config.ts";
import { resolveConfig } from "../../src/config/index.ts";

type Value = string | number | boolean | readonly Value[] | Block;

interface Block {
  readonly [key: string]: Value;
}

/** An object literal with unquoted keys, as an app writes its config. */
function literal(value: Value, depth = 0): string {
  if (typeof value !== "object") {
    return JSON.stringify(value);
  }

  if (Array.isArray(value)) {
    return `[${value.map((item) => literal(item, depth + 1)).join(", ")}]`;
  }

  const pad = "  ".repeat(depth + 1);

  return `{\n${Object.entries(value)
    .map(([key, item]) => `${pad}${key}: ${literal(item, depth + 1)},\n`)
    .join("")}${"  ".repeat(depth)}}`;
}

/**
 * Every protected option once, next to a `columns` entry the codemod removes (a
 * tenant that repeats `sql.tenantColumn`).
 */
const BLOCKS: Block = {
  memberships: {
    names: { organization: "workspace" },
    functions: { create_organization: "start_workspace" },
    permissions: { invite: "workspace.members.invite" },
    options: { roles: { many: true } },
    ownTablePolicies: "app",
    api: false,
    columns: { memberships: { tenant: "org_id", role: "team_role" } },
  },
  organizations: {
    options: {
      reservedSlugs: ["admin", "api"],
      slugPattern: "^[a-z0-9-]+$",
      slugMinLength: 3,
      slugMaxLength: 40,
    },
  },
  invitations: {
    options: { onAccept: { roles: true }, previewColumns: ["email"] },
  },
  audit: {
    options: {
      restricted: true,
      ipHeader: "x-real-ip",
      staffClaim: "staff",
      subjectColumns: { tasks: { subject: "task_id" } },
      exempt: [{ table: "public.trade_types", reason: "reference data" }],
    },
  },
  attachments: { options: { sources: ["public.tasks"] } },
};

const POWERSYNC: Block = { powersync: { sources: ["public.tasks"] } };

/**
 * PowerSync sits at the top of a grouped config and under `database` in a flat
 * one.
 */
const LAYOUTS: Readonly<Record<string, Block>> = {
  grouped: { sql: { tenantColumn: "org_id" }, blocks: BLOCKS, ...POWERSYNC },
  flat: {
    sql: { tenantColumn: "org_id" },
    blocks: BLOCKS,
    database: POWERSYNC,
  },
};

const run = async (config: Block): Promise<{ text: string; out: string }> => {
  const text = literal(config);

  const result = await configCodemod().project!({
    // SAFETY: the object holds only config keys the resolver reads.
    config: resolveConfig(config, "/nowhere"),
    sql: [],
    configFile: "better-supabase.config.ts",
    configText: text,
  });

  return { text, out: result.files[0]?.contents ?? text };
};

describe("the config codemod's protected options", () => {
  it.each(Object.entries(LAYOUTS))(
    "keeps every protected option in a %s config",
    async (_layout, config) => {
      const { text, out } = await run(config);

      for (const option of PROTECTED_OPTIONS) {
        expect(text, `${option} is in the fixture`).toContain(option);
        expect(out, `${option} survives`).toContain(option);
      }

      expect(out).toContain('role: "team_role"');
      expect(out).toContain('tenantColumn: "org_id"');
      expect(out).not.toContain('tenant: "org_id"');
    },
  );
});
