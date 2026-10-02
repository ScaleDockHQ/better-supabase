import { createClient } from "@supabase/supabase-js";
import { defineSupabase } from "better-supabase";
import { describe, expect, expectTypeOf, it, vi } from "vitest";

import { createCustomersService, type CustomersService } from "./customers.ts";
import { type Json, schema } from "./generated.ts";

const ORG = "00000000-0000-4000-8000-0000000000aa";

function service(body: Json = []) {
  const fetch = vi.fn<typeof globalThis.fetch>(() =>
    Promise.resolve(
      Response.json(body, { headers: { "content-range": "0-0/1" } }),
    ),
  );
  const client = createClient("https://crm.test", "sb_publishable_test", {
    global: { fetch },
  });
  const requests = () =>
    fetch.mock.calls.map(([input, init]) => {
      const url = new URL(String(input));
      return {
        method: init?.method ?? "GET",
        path: url.pathname,
        params: Object.fromEntries(url.searchParams),
      };
    });
  return {
    customers: createCustomersService(defineSupabase(schema).connect(client)),
    requests,
  };
}

describe("CRM customers on better-supabase", () => {
  it("lists customers with every filter in a single request", async () => {
    const { customers, requests } = service();
    await customers
      .listCustomers(ORG, {
        q: "acme",
        assigneeIds: ["u1"],
        unassigned: true,
        tagIds: ["t1"],
        types: ["business"],
        sortBy: "updatedAt",
        sortDirection: "desc",
        page: 2,
        size: 10,
      })
      .orThrow();

    const [request, ...rest] = requests();
    expect(rest).toEqual([]);
    expect(request!.path).toBe("/rest/v1/customers");
    expect(request!.params["organization_id"]).toBe(`eq.${ORG}`);
    expect(request!.params["status"]).toBe("neq.archived");
    expect(request!.params["is_business"]).toBe("eq.true");
    expect(request!.params["order"]).toBe("updated_at.desc,id.asc");
    expect(request!.params["offset"]).toBe("10");
    expect(request!.params["limit"]).toBe("11");
    expect(request!.params["select"]).toContain("customer_tags!");
    expect(request!.params["select"]).toContain("contact_profiles");
    expect(request!.params["or"]).toMatch(
      /^\(company_name\.ilike\."%acme%",sort_name\.ilike\."%acme%",billing_email\.ilike\."%acme%",_bs\d+\.not\.is\.null\)$/,
    );
  });

  it("types list rows with their includes", () => {
    type Page = Awaited<
      ReturnType<ReturnType<CustomersService["listCustomers"]>["orThrow"]>
    >;
    type Row = Page["items"][number];
    expectTypeOf<Row["id"]>().toEqualTypeOf<number>();
    expectTypeOf<Row["status"]>().toEqualTypeOf<
      "prospect" | "active" | "archived"
    >();
    expectTypeOf<Row["customerTags"][number]["tag"]>().toEqualTypeOf<{
      id: string;
      name: string;
      color: string | null;
    }>();
    expectTypeOf<
      Row["customerContacts"][number]["contactProfile"]
    >().toEqualTypeOf<{
      firstName: string | null;
      lastName: string | null;
      displayName: string | null;
    }>();
  });

  it("maps a delete blocked by linked records to a conflict", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(() =>
      Promise.resolve(
        Response.json(
          {
            code: "23503",
            message:
              'update or delete on table "customers" violates foreign key constraint',
          },
          { status: 409 },
        ),
      ),
    );
    const client = createClient("https://crm.test", "sb_publishable_test", {
      global: { fetch },
    });
    const customers = createCustomersService(
      defineSupabase(schema).connect(client),
    );
    const result = await customers.deleteCustomer(1);
    expect(result).toMatchObject({
      ok: false,
      error: { kind: "conflict", status: 409 },
    });
  });
});
