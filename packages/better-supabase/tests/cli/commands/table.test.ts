import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { run } from "../../../src/cli/core/run.ts";

describe("table", () => {
  let dir: string;
  const file = () => join(dir, "supabase/schemas/public/tables/invoices.sql");

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-table-"));
    await mkdir(join(dir, "supabase/schemas/public/tables"), {
      recursive: true,
    });
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({ blocks: [] }),
    );
    await writeFile(
      file(),
      "create table public.invoices (id uuid primary key);\n",
    );
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("enables and disables a feature in the table comment", async () => {
    const on = await run([
      "table",
      "invoices",
      "enable",
      "realtime",
      "--cwd",
      dir,
    ]);

    expect(on.code).toBe(0);
    expect(await readFile(file(), "utf-8")).toContain(
      "comment on table public.invoices is '@bsb realtime';",
    );

    const off = await run([
      "table",
      "invoices",
      "disable",
      "realtime",
      "--cwd",
      dir,
    ]);

    expect(off.code).toBe(0);
    expect(await readFile(file(), "utf-8")).toContain(
      "comment on table public.invoices is '';",
    );
  });

  it("writes nothing on a dry run and rejects unknown input", async () => {
    const dry = await run([
      "table",
      "invoices",
      "enable",
      "audit",
      "--dry-run",
      "--cwd",
      dir,
    ]);

    expect(dry.code).toBe(0);
    expect(await readFile(file(), "utf-8")).not.toContain("@bsb");

    const bad = await run([
      "table",
      "invoices",
      "enable",
      "nope",
      "--cwd",
      dir,
    ]);

    expect(bad.code).not.toBe(0);

    const missing = await run([
      "table",
      "orders",
      "enable",
      "audit",
      "--cwd",
      dir,
    ]);

    expect(missing.code).not.toBe(0);
  });
});
