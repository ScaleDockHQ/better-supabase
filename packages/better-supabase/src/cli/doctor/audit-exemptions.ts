import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { tenantNameOf } from "../../config/index.ts";
import { auditExemptTag, blockTables } from "../../sql/index.ts";
import { errorText } from "../core/errors.ts";
import { exemptions, globs, moduleOwned } from "./audit-coverage.ts";
import { ident as sqlIdent, literal as sqlString } from "./live.ts";
import { catalogOf, qualified, tableObject } from "./shared.ts";

interface LastEvent {
  readonly name: string;
  readonly last: string | null;
}

interface Exempted {
  readonly table: string;
  readonly reason: string;
  readonly object: FindingInput["object"];
}

/** The most tables one run reports. */
const LIMIT = 200;

/** The tables BS315 skips because an exemption or a tag names them. */
function exemptedTables(context: DoctorContext): Exempted[] {
  const entries = exemptions(
    context.config.blocks["audit"]?.options?.["exempt"],
  );

  const patterns = entries
    .filter((entry) => !entry.noTenantColumn)
    .map((entry) => ({ entry, pattern: globs([entry.glob])[0] }));

  const untenanted = entries.find((entry) => entry.noTenantColumn);

  const tenantColumn =
    context.config.sql.tenantColumn ??
    `${tenantNameOf(context.config.blocks) ?? "organization"}_id`;

  const owned = moduleOwned(context);

  return catalogOf(context).tables.flatMap((table): Exempted[] => {
    const name = qualified(table);

    if (
      table.kind !== "table" ||
      table.partitionOf !== undefined ||
      !context.config.schemas.includes(table.schema) ||
      owned.schemas.has(table.schema) ||
      owned.tables.has(name)
    ) {
      return [];
    }

    const tag = auditExemptTag(table.comment ?? null);

    const match =
      patterns.find(({ pattern }) => pattern?.test(name) === true)?.entry ??
      (untenanted !== undefined &&
      !table.columns.some((column) => column.name === tenantColumn)
        ? untenanted
        : undefined);

    if (tag === undefined && match === undefined) {
      return [];
    }

    const reason = match?.reason ?? tag?.reason ?? "no reason given";

    return [{ table: name, reason, object: tableObject(table) }];
  });
}

export const AUDIT_EXEMPTION_RULES: readonly Rule[] = [
  {
    code: "BS639",
    severity: "info",
    title: "Tables left out of the audit log",
    description:
      "One finding per table that BS315 skips because `blocks.audit.options.exempt` or an `@bsb audit-exempt` tag names it, with the reason and the time of the table's last entry in `better_supabase.audit_events`, or `never`. A table that had entries before its exemption shows when they stopped. Review the list when a table's purpose changes. Needs a database; saved snapshots skip it.",
    async check(context) {
      const db = context.database;

      if (
        !db ||
        "skipped" in db ||
        !context.config.blockNames.includes("audit")
      ) {
        return [];
      }

      const log = blockTables(context.config).byBlock["audit"]?.["log"];

      const columns: Readonly<Record<string, string | null>> =
        log?.columns ?? {};

      const tableColumn = columns["table"];
      const occurredAt = columns["occurredAt"];
      const exempted = exemptedTables(context).slice(0, LIMIT);

      if (!log || !tableColumn || !occurredAt || exempted.length === 0) {
        return [];
      }

      try {
        const names = exempted.map((each) => sqlString(each.table)).join(", ");

        const rows = await db.query<LastEvent>(
          `select t.name, (
            select max(l.${sqlIdent(occurredAt)}) from ${log.table} l where l.${sqlIdent(tableColumn)} = t.name
          )::text as last
          from unnest(array[${names}]::text[]) t (name)`,
        );

        const last = new Map(rows.map((row) => [row.name, row.last]));

        return exempted.map((each) => ({
          message: `${each.table} is left out of the audit log (${each.reason}). Last audit entry: ${last.get(each.table) ?? "never"}.`,
          target: each.table,
          ...(each.object === undefined ? {} : { object: each.object }),
        }));
      } catch (error) {
        return [
          {
            message: `Couldn't read the last audit entry of the exempt tables: ${errorText(error)}`,
            target: log.table,
          },
        ];
      }
    },
  },
];
