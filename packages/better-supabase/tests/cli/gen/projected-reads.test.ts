import { describe, expect, it } from "vitest";

import type { SchemaMeta, TableMeta } from "../../../src/index.ts";

import {
  NO_PROJECTED_READS,
  projectedReads,
} from "../../../src/cli/gen/projected-reads.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const table = (
  key: string,
  schema: string,
  name: string,
  kind: TableMeta["kind"],
): TableMeta => ({
  key,
  name,
  schema,
  kind,
  columns: {},
  primaryKey: [],
  uniqueKeys: {},
  relations: {},
  flags: {},
});

const meta: SchemaMeta = {
  version: 1,
  casing: "camel",
  tables: {
    jobAttachments: table(
      "jobAttachments",
      "public",
      "job_attachments",
      "view",
    ),
    attachments: table(
      "attachments",
      "better_supabase",
      "attachments",
      "table",
    ),
    jobs: table("jobs", "public", "jobs", "table"),
  },
  enums: {},
  functions: {},
};

const VIEW =
  "create view public.job_attachments with (security_invoker = true) as select id, tenant_id as organization_id from better_supabase.attachments where subject_type = 'job';";

const config = resolveConfig({ blocks: { attachments: {} } }, "/project");

describe("projectedReads", () => {
  it("keys the views over a block table, and the table's own key", () => {
    const found = projectedReads(config, meta, [{ text: VIEW }]);

    expect(found.viewKeys).toStrictEqual(
      new Map([["better_supabase.attachments", ["jobAttachments"]]]),
    );
    expect([...found.baseKeys]).toStrictEqual(["attachments"]);
  });

  it("ignores a view over the app's own table", () => {
    expect(
      projectedReads(config, meta, [
        { text: "create view public.open_jobs as select id from public.jobs;" },
      ]),
    ).toStrictEqual(NO_PROJECTED_READS);
  });

  it("ignores a view the typed client doesn't key", () => {
    expect(
      projectedReads(
        config,
        { ...meta, tables: { jobs: meta.tables["jobs"]! } },
        [{ text: VIEW }],
      ),
    ).toStrictEqual(NO_PROJECTED_READS);
  });

  it("finds nothing without blocks", () => {
    expect(
      projectedReads(resolveConfig({}, "/project"), meta, [{ text: VIEW }]),
    ).toStrictEqual(NO_PROJECTED_READS);
  });
});
