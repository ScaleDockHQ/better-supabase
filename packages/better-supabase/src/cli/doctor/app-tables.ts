import type { BlockSqlLayout } from "../../sql/index.ts";
import type { AccessProviderMode } from "../authorization.ts";
import type { DoctorContext } from "./rules.ts";

import { declaredTables, resolveBlocks } from "../../sql/index.ts";
import { accessProviderMode } from "../authorization.ts";
import { writtenByBlocks } from "../sql-layout.ts";
import { catalogOf, qualified } from "./shared.ts";

/**
 * The app's tables in the database, as `ownTables`: those in `schemas` that no
 * block file or module migration creates.
 */
export function appTablesOf(
  context: DoctorContext,
): Readonly<Record<string, string>> {
  const created = new Set(
    declaredTables(
      (context.sqlFiles ?? []).filter(writtenByBlocks),
      context.config.schemas,
    ),
  );

  return Object.fromEntries(
    catalogOf(context)
      .tables.filter(
        (table) =>
          context.config.schemas.includes(table.schema) &&
          !created.has(qualified(table)),
      )
      .map((table) => [qualified(table), "database"]),
  );
}

/**
 * The views among the app's tables, and the columns of each, for the layout a
 * block reads them with.
 */
export function appViewsOf(
  context: DoctorContext,
): Required<Pick<BlockSqlLayout, "ownViews" | "ownColumns">> {
  const own = appTablesOf(context);

  const views = catalogOf(context).tables.filter(
    (table) => table.kind === "view" && Object.hasOwn(own, qualified(table)),
  );

  return {
    ownViews: Object.fromEntries(
      views.map((view) => [
        qualified(view),
        { updatable: view.insertable && view.updatable },
      ]),
    ),
    ownColumns: Object.fromEntries(
      views.map((view) => [
        qualified(view),
        view.columns.map((column) => column.name),
      ]),
    ),
  };
}

/**
 * The provider for the `provider` access model, when `blocks` installs
 * `access`.
 */
export function accessModule(
  context: Pick<DoctorContext, "config">,
): AccessProviderMode {
  if (
    !resolveBlocks(context.config.blockNames, {}).some(
      (module) => module.name === "permissions",
    )
  ) {
    return { kind: "off" };
  }

  return accessProviderMode(context.config);
}

/** What `adoptedTables` needs to render the modules as `upgrade` does. */
export function adoptionContext(
  context: Pick<DoctorContext, "config">,
): Pick<BlockSqlLayout, "subjects" | "accessProvider"> {
  const access = accessModule(context);

  return {
    subjects: context.config.subjects,
    ...(access.kind === "provider" ? { accessProvider: access.access } : {}),
  };
}
