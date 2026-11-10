import type { BlockSqlContext } from "../context.ts";

import { subjectsOption } from "../subjects.ts";
import { documentsOn, storageStatusBackfill } from "./attachments-documents.ts";
import { pathExpression } from "./attachments-path.ts";

/**
 * The statements that bring rows written before a schema change in line with
 * it: a path that no longer matches `options.path`, and a record uploaded
 * before the storage status existed. They change rows, so they run with the
 * data file and a schema diff never sees them.
 */
export function attachmentBackfills(ctx: BlockSqlContext): string {
  const t = ctx.table("attachments");
  const c = (logical: string): string => ctx.col("attachments", logical);

  const tenantless = subjectsOption(
    ctx,
    ["bucket", "allowedMimeTypes", "permissions", "scope"],
    { tenantless: true },
  ).filter(([, subject]) => subject.tenant === false);

  // The trigger fills a null path again, so clearing it rewrites the row. A
  // stored object stays where it is, so its row keeps the path that finds it.
  const repath = ctx.owns("attachments")
    ? `
-- options.path: a row whose path no longer matches the template, and that has no stored object, gets a new one.
update ${t} as x set ${c("path")} = null
where x.${c("path")} is distinct from (select ${pathExpression(ctx, tenantless.length > 0)} from (select x.*) as r)
  and not exists (select 1 from storage.objects o where o.bucket_id = x.${c("bucket")} and o.name = x.${c("path")});`
    : "";

  const status = documentsOn(ctx)
    ? `
-- A record uploaded before the storage status existed is stored.
${storageStatusBackfill(t, c)}`
    : "";

  return `${repath}${status}`;
}
