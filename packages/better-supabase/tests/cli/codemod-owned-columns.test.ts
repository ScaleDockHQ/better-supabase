import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { ownedColumnsCodemod } from "../../src/cli/codemod-owned-columns.ts";
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

    expect(result.review).toEqual([]);
    expect(result.files.length).toBeGreaterThan(0);

    const reminders = result.files.find((file) =>
      file.path.endsWith("reminders.block-columns.sql"),
    );

    expect(reminders?.policy).toBe("create");
    expect(reminders?.contents).toContain(
      'alter table "public"."reminders" add column if not exists',
    );
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

  it("explains a project whose blocks don't render", async () => {
    const result = await ownedColumnsCodemod().project!({
      config: { ...config, blockNames: ["no-such-block"] },
      sql: [],
    });

    expect(result.files).toEqual([]);
    expect(result.review[0]?.message).toContain("don't render");
  });
});
