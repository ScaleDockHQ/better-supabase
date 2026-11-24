import { describe, expect, it } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { postgresExecutor } from "../../src/postgres/executor.ts";
import { shareGuard } from "../../src/server/tenant-share.ts";
import { inTenantFill } from "../../src/testing/tenant-fill.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { schema } from "../fixtures/generated-camel.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const claims = { sub: USER, role: "authenticated" };

describe("inTenantFill", () => {
  const db = createSupabase(schema).connect(postgresExecutor(fakeSql().sql), {
    claims,
  });

  const ctx = { auth: { kind: "user" as const, claims }, db };

  it("passes the entry's tables and reports no refusal", async () => {
    const fill = await inTenantFill(ctx, ["customers"], (shared) =>
      shareGuard(shared, db).customers.list({ select: ["id"] }),
    );

    expect(fill.value.ok).toBe(true);
    expect(fill.refused).toBeUndefined();
  });

  it("reports the first read outside the entry's tables", async () => {
    const fill = await inTenantFill(ctx, ["customers"], (shared) =>
      shared.db.contacts.list({ select: ["id"] }),
    );

    expect(fill.value.error?.code).toBe("SHARE_REFUSED");
    expect(fill.refused?.table).toBe("contacts");
  });
});
