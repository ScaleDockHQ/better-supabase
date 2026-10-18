"use server";

import { DbException, dbError, err, ok, type Result } from "better-supabase";
import { rpcTransport } from "better-supabase/blocks";
import {
  defineImport,
  dryRun,
  type ImportRowError,
  runImport,
} from "better-supabase/blocks/imports";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bs } from "@/lib/supabase/server";

import { CUSTOMER_IMPORT_FIELDS } from "./imports-fields";

const API_SCHEMA = blockConfig.imports.api;
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
export const previewCustomerImport = bs.action(
  {
    input: Input,
    requireTenant: true,
    authorize: (session) => can(session, "imports.manage"),
  },
  async ({ csv, mapping }, { db }) => {
    const preview = await dryRun(
      customerImport((rows) => db.customers.createMany(rows)),
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
 * `finish_import` is granted to the service role only, so it runs as that
 * role after the caller passed `imports.manage`.
 */
export const runCustomerImport = bs.action(
  {
    input: Input,
    requireTenant: true,
    authorize: (session) =>
      can(session, "imports.manage") && can(session, "customers.write"),
  },
  async ({ csv, mapping }, { tenant, db, supabase, auth }) => {
    const existing = await db.customers.findMany({
      select: ["name"],
      where: { organizationId: tenant },
      limit: 10_000,
    });

    if (!existing.ok) {
      return existing;
    }

    const service = rpcTransport(bs.admin().$client, { schema: API_SCHEMA });

    const finish = async (
      id: string,
      status: "completed" | "failed",
      count: number,
      error: string | null,
    ) => {
      try {
        await service.call(API_SCHEMA, "finish_import", {
          id,
          status,
          count,
          error,
        });
      } catch (cause) {
        throw new DbException(
          dbError(
            "unexpected",
            `Could not finish the import: ${String(cause)}`,
          ),
        );
      }
    };

    const definition = customerImport((rows) =>
      db.customers.createMany(rows, { returning: false }),
    );

    const { rows: valid } = await dryRun(definition, csv, mapping);
    let runId: string | undefined;

    try {
      const result = await runImport(definition, csv, mapping, {
        organizationId: tenant,
        importedKeys: new Set(
          existing.data.map((row) => row.name.toLowerCase()),
        ),
        start: async () => {
          const run = await blocks(supabase).imports.start(
            tenant,
            "customers",
            mapping,
          );

          if (!run.ok) {
            throw new DbException(run.error);
          }

          runId = run.data.id;

          return run.data.id;
        },
        finish,
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

      if (runId !== undefined) {
        await finish(runId, "failed", 0, error.message).catch(() => null);
      }

      return err(error.error);
    }
  },
);
