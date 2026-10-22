"use server";

import type { Result } from "better-supabase";
import type { ImportRowError } from "better-supabase/blocks/imports";

import { DbException, err, ok } from "better-supabase";
import {
  defineImport,
  dryRun,
  runImport,
} from "better-supabase/blocks/imports";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { importRunHooks } from "./import-run";
import { CUSTOMER_IMPORT_FIELDS } from "./imports-fields";

const PREVIEW_ROWS = 20;

/** An empty cell is a left-out value, so the column default applies. */
const optionalCell = <const T extends v.GenericSchema<string, string>>(
  schema: T,
) =>
  v.pipe(
    v.optional(v.string(), ""),
    v.trim(),
    v.transform((cell) => (cell === "" ? undefined : cell)),
    v.optional(schema),
  );

const CustomerRow = v.object({
  name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
  status: optionalCell(v.picklist(["lead", "active"])),
  kvk: optionalCell(v.pipe(v.string(), v.regex(/^\d{8}$/))),
});

export type CustomerRow = v.InferOutput<typeof CustomerRow>;

interface NewCustomer {
  readonly name: string;
  readonly organizationId: string;
  readonly status?: "lead" | "active";
  readonly kvk?: string;
}

function newCustomer(row: CustomerRow, organizationId: string): NewCustomer {
  const base = { name: row.name, organizationId };

  const withStatus =
    row.status === undefined ? base : { ...base, status: row.status };

  return row.kvk === undefined ? withStatus : { ...withStatus, kvk: row.kvk };
}

/** A row's key is its lowercased name, so a name already in the list is skipped. */
function customerImport(
  createMany: (rows: readonly NewCustomer[]) => PromiseLike<Result<unknown>>,
) {
  return defineImport<CustomerRow>({
    kind: "customers",
    columns: CustomerRow,
    key: (row) => row.name.toLowerCase(),
    insert: async (batch, { organizationId }) => {
      const created = await createMany(
        batch.map((row) => newCustomer(row, organizationId)),
      );

      if (!created.ok) {
        throw new DbException(created.error);
      }
    },
  });
}

const Input = v.object({
  csv: v.pipe(v.string(), v.minLength(1), v.maxLength(500_000)),
  mapping: v.record(v.string(), v.picklist(CUSTOMER_IMPORT_FIELDS)),
});

export interface ImportPreview {
  readonly valid: number;
  readonly rows: readonly CustomerRow[];
  readonly errors: readonly ImportRowError[];
}

/** Validates every row against the mapping. Nothing is written. */
export const previewCustomerImport = bsb.action(
  {
    input: Input,
    requireTenant: true,
    authorize: (session) => can(session, "imports.manage"),
  },
  async ({ csv, mapping }, { db }) => {
    const preview = await dryRun(
      customerImport((rows) => db.customers.create(rows)),
      csv,
      mapping,
    );

    return ok<ImportPreview>({
      valid: preview.rows.length,
      rows: preview.rows.slice(0, PREVIEW_ROWS),
      errors: preview.errors,
    });
  },
);

export interface ImportOutcome {
  readonly id: string;
  readonly status: "completed" | "failed";
  readonly imported: number;
  readonly skipped: number;
  readonly errors: readonly ImportRowError[];
}

/**
 * Records an import run, creates the new customers and finishes the run.
 * `finish_import` is granted to the service role only, so it runs as that role
 * after the caller passed `imports.manage`.
 */
export const runCustomerImport = bsb.action(
  {
    input: Input,
    requireTenant: true,
    authorize: (session) =>
      can(session, "imports.manage") && can(session, "customers.write"),
  },
  async ({ csv, mapping }, { tenant, db, supabase, auth }) => {
    const existing = await db.customers.list({
      select: ["name"],
      where: { organizationId: tenant },
      limit: 10_000,
    });

    if (!existing.ok) {
      return existing;
    }

    const definition = customerImport((rows) =>
      db.customers.create(rows, { returning: false }),
    );

    const { rows: valid } = await dryRun(definition, csv, mapping);
    const hooks = importRunHooks(supabase, tenant, "customers", mapping);

    try {
      const result = await runImport(definition, csv, mapping, {
        ...hooks,
        importedKeys: new Set(
          existing.data.map((row) => row.name.toLowerCase()),
        ),
      });

      refreshCaller(auth);

      return ok<ImportOutcome>({
        id: result.id,
        status: result.status,
        imported: result.imported,
        skipped:
          result.status === "completed" ? valid.length - result.imported : 0,
        errors: result.errors,
      });
    } catch (error) {
      if (!(error instanceof DbException)) {
        throw error;
      }

      await hooks.fail(error.message);

      return err(error.error);
    }
  },
);
