import type { PostgresApi } from "@supabase/server/middleware/postgres";

import { describe, expectTypeOf, it } from "vitest";

import type { SqlClient } from "../../src/postgres/executor.ts";

import { purgeAuditLog } from "../../src/blocks/audit/index.ts";
import { entitlementMembers } from "../../src/blocks/entitlements/index.ts";
import {
  createIdempotency,
  createInbox,
  createJobs,
} from "../../src/blocks/jobs/index.ts";
import { createOutbox } from "../../src/blocks/outbox/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";

declare const postgres: PostgresApi;
declare const postgresAdmin: PostgresApi;

describe("blocks on @supabase/server's Postgres clients", () => {
  it("take ctx.postgres and ctx.postgresAdmin wherever they take a SqlClient", () => {
    expectTypeOf(postgres).toExtend<SqlClient>();
    sqlTransport(postgres);
    createJobs(postgresAdmin, {});
    createIdempotency(postgresAdmin);
    createInbox(postgresAdmin, { source: "stripe", secrets: "whsec_x" });
    purgeAuditLog(postgresAdmin);
    createOutbox(postgresAdmin, { source: "app" });
    void entitlementMembers(postgresAdmin, "cus_1");
  });
});
