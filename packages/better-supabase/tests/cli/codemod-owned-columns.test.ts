import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { ownedColumnsCodemod } from "../../src/cli/codemod-owned-columns.ts";
import { runCodemod } from "../../src/cli/commands/codemod.ts";
import { resolveConfig } from "../../src/config/index.ts";

const APP = `create table public.reminders (id uuid primary key, organization_id uuid not null);
create table public.reminder_rules (id uuid primary key, organization_id uuid not null);
create table public.reminder_deliveries (id uuid primary key, organization_id uuid not null);`;

const root = mkdtempSync(join(tmpdir(), "bsb-owned-"));

mkdirSync(join(root, "supabase/schemas"), { recursive: true });

writeFileSync(join(root, "supabase/schemas/app.sql"), APP);

const config = resolveConfig(
  {
    blocks: {
      reminders: {
        tables: {
          rules: "public.reminder_rules",
          reminders: "public.reminders",
          deliveries: "public.reminder_deliveries",
        },
      },
    },
  },
  root,
);

const project = (sql: readonly { path: string; text: string }[]) => ({
  config,
  sql,
});

describe("the owned-columns codemod", () => {
  it("declares the columns a block adds to a table the app creates", async () => {
    const result = await ownedColumnsCodemod().project!(
      project([{ path: "/nowhere/supabase/schemas/app.sql", text: APP }]),
    );

    expect(result.review.map((line) => line.message)).toEqual([
      'blocks.reminders.columns.rules.rrule is optional, and the database or snapshot has no "rrule" column on public.reminder_rules. Set it to null to keep the feature off.',
      'blocks.reminders.columns.reminders.remindAt is optional, and the database or snapshot has no "remind_at" column on public.reminders. Set it to null to keep the feature off.',
    ]);
    expect(result.files.length).toBeGreaterThan(0);

    const reminders = result.files.find((file) =>
      file.path.endsWith("reminders.block-columns.sql"),
    );

    expect(reminders?.policy).toBe("create");
    expect(reminders?.contents).toContain(
      'alter table "public"."reminders" add column if not exists',
    );
  });

  it("keeps an optional column the live database has, though the snapshot lacks it", async () => {
    const result = await ownedColumnsCodemod().project!({
      ...project([{ path: "/nowhere/supabase/schemas/app.sql", text: APP }]),
      liveColumns: () =>
        Promise.resolve(
          new Map([
            ["public.reminder_rules", new Set(["rrule"])],
            ["public.reminders", new Set(["remind_at"])],
          ]),
        ),
    });

    const declared = result.files.map((file) => file.contents).join("\n");

    expect(result.review).toEqual([]);
    expect(declared).toContain('"remind_at"');
    expect(declared).toContain('"rrule"');
  });

  it("tries the database from the command, and falls back when it is down", async () => {
    const result = await runCodemod(
      config,
      { _: ["owned-columns"], "dry-run": true },
      undefined,
      undefined,
      undefined,
      { DATABASE_URL: "postgresql://postgres@127.0.0.1:1/postgres" },
    );

    expect(JSON.stringify(result)).toContain("rrule");
  });

  it("reads the snapshot alone when the database can't be read", async () => {
    const result = await ownedColumnsCodemod().project!({
      ...project([{ path: "/nowhere/supabase/schemas/app.sql", text: APP }]),
      liveColumns: () => Promise.resolve(undefined),
    });

    expect(result.review).toHaveLength(2);
  });

  it("finds nothing once the files declare them, and ignores block files and migrations", async () => {
    const first = await ownedColumnsCodemod().project!(
      project([{ path: "/nowhere/supabase/schemas/app.sql", text: APP }]),
    );

    const again = await ownedColumnsCodemod().project!(
      project([
        { path: "/nowhere/supabase/schemas/app.sql", text: APP },
        ...first.files.map((file) => ({
          path: file.path,
          text: file.contents,
        })),
        {
          path: "/nowhere/supabase/migrations/1_x.sql",
          text: "create table public.other (id uuid);",
        },
        {
          path: "/nowhere/supabase/schemas/900_better_supabase_001_x.sql",
          text: "create table public.blocky (id uuid);",
        },
      ]),
    );

    expect(again.files).toEqual([]);
  });

  it("fails config_invalid for a project whose blocks don't render", async () => {
    await expect(
      ownedColumnsCodemod().project!({
        config: { ...config, blockNames: ["no-such-block"] },
        sql: [],
      }),
    ).rejects.toMatchObject({
      code: "config_invalid",
      message: expect.stringContaining("don't render"),
    });
  });

  it("skips an unknown module and a column the config turns off", async () => {
    const result = await ownedColumnsCodemod().project!({
      config: {
        ...config,
        blocks: {
          ...config.blocks,
          reminders: {
            ...config.blocks["reminders"],
            columns: { rules: { rrule: null } },
          },
        },
        instances: {
          extra: {
            name: "extra",
            block: "not-real",
            uses: {},
            config: { columns: { rows: { reason: null } } },
          },
        },
      },
      sql: [{ path: "/nowhere/supabase/schemas/app.sql", text: APP }],
    });

    expect(result.files.length).toBeGreaterThan(0);
    expect(result.review.some((line) => line.message.includes("rrule"))).toBe(
      false,
    );
  });

  it("reviews a column the app still has under the old name", async () => {
    const dir = mkdtempSync(join(tmpdir(), "bsb-pin-"));

    const sql =
      "create table public.drive_nodes (id uuid primary key, deleted_at timestamptz);\n";

    mkdirSync(join(dir, "supabase/schemas"), { recursive: true });
    writeFileSync(join(dir, "supabase/schemas/app.sql"), sql);

    const pinned = resolveConfig(
      { blocks: { drive: { tables: { nodes: "public.drive_nodes" } } } },
      dir,
    );

    const result = await ownedColumnsCodemod().project!({
      config: {
        ...pinned,
        blocks: {
          ...pinned.blocks,
          invoices: { tables: { notATable: "public.x" } },
        },
      },
      sql: [{ path: join(dir, "supabase/schemas/app.sql"), text: sql }],
    });

    expect(
      result.review.some((line) => line.message.includes("left out")),
    ).toBe(true);
  });
});
