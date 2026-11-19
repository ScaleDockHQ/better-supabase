import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";
import { moduleProvider } from "../fixtures/authorization-provider.ts";

const provider = {
  ...moduleProvider,
  functions: {
    ...moduleProvider.functions,
    rowsWith: "authz.rows_{resource}({permission}, {ids})",
  },
};

const job = {
  table: "public.jobs",
  idType: "uuid",
  tenant: "organization_id",
  permissions: {
    read: { key: "jobs.read", rows: "jobs" },
    upload: { key: "jobs.update", rows: "jobs" },
  },
};

const sqlOf = (
  module: string,
  modules: Readonly<Record<string, unknown>>,
): string =>
  renderBlocks([module], {
    subjects: { job },
    modules: { permissions: { model: "provider" }, ...modules },
    accessProvider: provider,
  })
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("a registered action granted per row", () => {
  it("lets an attachment upload pass on the job row's grant", () => {
    const sql = sqlOf("attachments", { attachments: { on: ["job"] } });

    const insert = sql.slice(
      sql.indexOf("create policy bsb_attachments_insert"),
    );

    expect(insert).toContain(
      `exists (select 1 from "public"."jobs" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id" and ("better_supabase"."attachments"."tenant_id" in (select better_supabase.tenant_ids_with('jobs.update')) or s."id"::text in (select r.id::text from authz.rows_jobs('jobs.update', array[s."id"::text]) as r(id))))`,
    );
    expect(insert).not.toContain(
      `'job' and ("better_supabase"."attachments"."tenant_id" in (select better_supabase.tenant_ids_with('jobs.update'))))`,
    );
  });

  it("keeps the tenant key when the action is a plain key", () => {
    const sql = renderBlocks(["attachments"], {
      subjects: {
        job: {
          ...job,
          permissions: { read: "jobs.read", upload: "jobs.update" },
        },
      },
      modules: { attachments: { on: ["job"] } },
    })
      .filter((file) => file.module === "attachments")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `("better_supabase"."attachments"."subject_type" = 'job' and ("better_supabase"."attachments"."tenant_id" in (select better_supabase.tenant_ids_with('jobs.update'))))`,
    );
    expect(sql).not.toContain("authz.rows_jobs");
  });

  it("reads deadlines through the job row when the module reads with the job's key", () => {
    const sql = sqlOf("deadlines", {
      deadlines: { on: ["job"], permissions: { read: "jobs.read" } },
    });

    const read = sql.slice(sql.indexOf("create policy bsb_deadlines_read"));

    expect(read).toContain(
      `using (("tenant_id" in (select better_supabase.tenant_ids_with('jobs.read')) or ("better_supabase"."deadlines"."subject_type" in ('job') and "better_supabase"."deadlines"."tenant_id" in (select better_supabase.member_organization_ids())))`,
    );
    expect(read).toContain("authz.rows_jobs('jobs.read'");
    expect(sql).toContain("not allowed to read deadlines");
    expect(sqlOf("deadlines", { deadlines: { on: ["job"] } })).not.toContain(
      `"subject_type" in ('job')`,
    );
  });
});
