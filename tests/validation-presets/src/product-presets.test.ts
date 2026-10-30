import type { PresetName } from "better-supabase/preset";
import type { PoolClient } from "pg";

import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, installAndRollBack, presetFiles, reachable } from "./stack.ts";

// The product presets installed on the local stack, checked for the links
// between their blocks: what the preset is for, beyond each block on its own.

const live = await reachable();

const installed = (name: PresetName): string =>
  presetFiles(name)
    .map((file) => file.contents)
    .join("\n\n");

async function tables(
  client: PoolClient,
  names: readonly string[],
): Promise<readonly string[]> {
  const { rows } = await client.query<{ name: string }>(
    "select name from unnest($1::text[]) as name where to_regclass('better_supabase.' || name) is null",
    [names],
  );

  return rows.map((row) => row.name);
}

async function columns(
  client: PoolClient,
  table: string,
): Promise<readonly string[]> {
  const { rows } = await client.query<{ column_name: string }>(
    "select column_name from information_schema.columns where table_schema = 'better_supabase' and table_name = $1",
    [table],
  );

  return rows.map((row) => row.column_name);
}

async function publicBucket(client: PoolClient, id: string): Promise<boolean> {
  const { rows } = await client.query<{ public: boolean }>(
    "select public from storage.buckets where id = $1",
    [id],
  );

  return rows[0]?.public ?? false;
}

/** The bodies of the module's functions whose names match a LIKE pattern. */
async function functionBody(
  client: PoolClient,
  pattern: string,
): Promise<string> {
  const { rows } = await client.query<{ body: string | null }>(
    "select string_agg(prosrc, ' ') as body from pg_proc where pronamespace = 'better_supabase'::regnamespace and proname like $1",
    [pattern],
  );

  return rows[0]?.body ?? "";
}

describe.skipIf(!live)("product presets on the local stack", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });

  afterAll(() => pool.end());

  it("crm installs the sales engagement blocks next to deals", async () => {
    await installAndRollBack(pool, installed("crm"), async (client) => {
      expect(
        await tables(client, [
          "deals",
          "sequences",
          "enrollments",
          "segments",
          "lead_score_checks",
          "forecast_snapshots",
        ]),
      ).toEqual([]);
      expect(await functionBody(client, "score_lead")).not.toBe("");
    });
  }, 120_000);

  it("cms serves media from a public bucket and publishes through approvals", async () => {
    await installAndRollBack(pool, installed("cms"), async (client) => {
      expect(await tables(client, ["content_entries"])).toEqual([]);
      expect(await publicBucket(client, "attachments")).toBe(true);
      expect(await functionBody(client, "publish_content_entry")).toContain(
        "approval",
      );
    });
  }, 120_000);

  it("erp invoices paid orders and keys time and leave to employees", async () => {
    await installAndRollBack(pool, installed("erp"), async (client) => {
      expect(await functionBody(client, "record_payment")).toContain(
        "create_invoice",
      );
      expect(await columns(client, "time_entries")).toContain("employee_id");
      expect(await columns(client, "leave_requests")).toContain("employee_id");
      expect(await functionBody(client, "%quote%")).toContain(
        "product_variants",
      );
    });
  }, 120_000);

  it("pim keeps channels, translations and public product media", async () => {
    await installAndRollBack(pool, installed("pim"), async (client) => {
      expect(
        await tables(client, [
          "catalog_channels",
          "product_translations",
          "product_media",
        ]),
      ).toEqual([]);
      expect(await publicBucket(client, "attachments")).toBe(true);
    });
  }, 120_000);

  it("qms releases controlled documents through approvals next to the quality blocks", async () => {
    await installAndRollBack(pool, installed("qms"), async (client) => {
      expect(
        await tables(client, [
          "acknowledgements",
          "case_kinds",
          "cases",
          "inspections",
          "inspection_findings",
          "risks",
          "qualification_types",
          "qualifications",
        ]),
      ).toEqual([]);
      expect(await functionBody(client, "%approval%")).toContain(
        "drive_document_decided",
      );
    });
  }, 120_000);

  // The fixture already holds every table, so the approval functions the
  // preset replaces are what tells the two apart.
  it("ehs keeps the drive without document control", async () => {
    await installAndRollBack(pool, installed("ehs"), async (client) => {
      expect(await tables(client, ["cases", "qualifications"])).toEqual([]);
      expect(await functionBody(client, "%approval%")).not.toContain(
        "drive_document_decided",
      );
    });
  }, 120_000);
});
