import type { AuditedTable } from "../sql/layout-types.ts";

import { factsOf } from "./schema-reader/index.ts";

/**
 * The tables `files` register with `better_supabase.audit(...)`, a static
 * `create trigger bsb_audit ... execute function
 * better_supabase.audit_row_change('{...}')`, or the `bsb_audit_stmt_*`
 * statement triggers, in file order: a later registration for the same table
 * replaces the earlier one, `unaudit(...)` or a `drop table` removes it, and
 * `alter table ... rename to` moves it to the new name. Calls with non-literal
 * arguments are skipped. The files are read first with `primeSchemaFacts`.
 */
export function auditRegistrations(
  files: readonly { readonly text: string }[],
): AuditedTable[] {
  const tables = new Map<string, AuditedTable>();

  for (const file of files) {
    for (const event of factsOf(file.text).audits) {
      switch (event.kind) {
        case "register": {
          tables.set(event.target, {
            target: event.target,
            ignore: event.ignore,
            redact: event.redact,
          });

          break;
        }

        case "unregister":
        case "drop": {
          tables.delete(event.target);

          break;
        }

        case "rename": {
          const entry = tables.get(event.target);

          if (entry !== undefined) {
            tables.delete(event.target);
            tables.set(event.to, { ...entry, target: event.to });
          }

          break;
        }

        default: {
          const unreachable: never = event;

          throw new Error(`Unknown audit fact ${JSON.stringify(unreachable)}`);
        }
      }
    }
  }

  return [...tables.values()].toSorted((a, b) =>
    a.target < b.target ? -1 : a.target > b.target ? 1 : 0,
  );
}
