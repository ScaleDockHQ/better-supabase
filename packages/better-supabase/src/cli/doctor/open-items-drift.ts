import type { FindingInput, Rule } from "./rules.ts";

import { blockFunction, blockTables } from "../../sql/block-tables.ts";
import { errorText } from "../core/errors.ts";
import { ident as sqlIdent, literal as sqlString } from "./live.ts";

interface DriftRow {
  readonly tenant: string;
  readonly drift: number;
}

export const OPEN_ITEMS_DRIFT_RULES: readonly Rule[] = [
  {
    code: "BS638",
    severity: "warning",
    title: "Stored open items differ from the fold",
    description:
      "`invoice_open_items` keeps today's open invoices and unallocated payments so `open_items_for_party` and `open_items_page` read one table. Triggers keep it current; a write that skips them (a restore, a manual `update` with triggers off) leaves rows that differ from the fold over invoices and ledger entries. Doctor calls `open_items_drift_rows` for each organization with stored rows or invoices and lists the ones that differ. Run `rebuild_open_items(tenant)` for each. Needs a database; saved snapshots skip it.",
    async check(context) {
      const db = context.database;

      if (!db || "skipped" in db) {
        return [];
      }

      const tables = blockTables(context.config).byBlock["invoices"];
      const store = tables?.["openItems"];
      const invoices = tables?.["invoices"];

      const drift = blockFunction(
        context.config,
        "invoices",
        "open_items_drift_rows",
      );

      const storeColumns: Readonly<Record<string, string | null>> =
        store?.columns ?? {};

      const invoiceColumns: Readonly<Record<string, string | null>> =
        invoices?.columns ?? {};

      const storeTenant = storeColumns["tenant"];
      const invoiceTenant = invoiceColumns["tenant"];

      if (!store || !invoices || !drift || !storeTenant || !invoiceTenant) {
        return [];
      }

      try {
        const [installed] = await db.query<{ found: boolean }>(
          `select to_regproc(${sqlString(drift)}) is not null as found`,
        );

        if (!installed?.found) {
          return [];
        }

        const rows = await db.query<DriftRow>(
          `select d.tenant, d.drift from (
            select t.tenant::text as tenant, jsonb_array_length(${drift}(t.tenant))::int as drift from (
              select ${sqlIdent(storeTenant)} as tenant from ${store.table}
              union
              select ${sqlIdent(invoiceTenant)} from ${invoices.table}
            ) t
          ) d
          where d.drift > 0
          order by 1
          limit 20`,
        );

        const findings: FindingInput[] = rows.map((row) => ({
          message: `${String(row.drift)} stored open item${row.drift === 1 ? "" : "s"} of organization ${row.tenant} differ from the fold over invoices and ledger entries. Run select rebuild_open_items('${row.tenant}') to write them again.`,
          target: store.table,
        }));

        return findings;
      } catch (error) {
        return [
          {
            message: `Couldn't compare the stored open items: ${errorText(error)}`,
            target: store.table,
          },
        ];
      }
    },
  },
];
