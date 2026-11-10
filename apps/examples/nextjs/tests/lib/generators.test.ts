import { describe, expect, it } from "vitest";

import { factories } from "../../src/lib/supabase/generated.factories.ts";
import {
  customersSearchParams,
  loadCustomersSearchParams,
  serializeCustomersSearchParams,
} from "../../src/lib/supabase/generated.nuqs.ts";
import { customersInsert } from "../../src/lib/supabase/generated.zod.ts";

const ORGANIZATION = "00000000-0000-4000-8000-000000000001";

describe("first-party generators", () => {
  it("builds a factory row the generated zod schema accepts", () => {
    const row = factories.customers({ organizationId: ORGANIZATION });

    expect(customersInsert.safeParse(row).success).toBe(true);
    expect(customersInsert.safeParse({ ...row, name: undefined }).success).toBe(
      false,
    );
  });

  it("round-trips the nuqs list params through a URL", () => {
    const url = serializeCustomersSearchParams("/customers", {
      status: "active",
      limit: 50,
    });

    expect(url).toBe("/customers?status=active&limit=50");
    expect(
      loadCustomersSearchParams(new URL(url, "https://app.test").searchParams),
    ).toMatchObject({ status: "active", limit: 50, direction: "asc" });
    expect(Object.keys(customersSearchParams)).toContain("cursor");
  });
});
