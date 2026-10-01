import type { Result } from "better-supabase";

import { describe, expectTypeOf, it } from "vitest";

import type { customerById } from "./crm/customers.ts";
import type { Db } from "./runtime/index.ts";

import { shippingAddresses } from "./commerce/shipping.ts";
import { activeCustomers } from "./crm/customers.ts";

describe("repositories typed from the runtime's db", () => {
  it("take the runtime Db and return camel-cased rows", () => {
    expectTypeOf(activeCustomers).parameter(0).toEqualTypeOf<Db>();
    expectTypeOf(shippingAddresses).parameter(0).toEqualTypeOf<Db>();
    expectTypeOf<Awaited<ReturnType<typeof customerById>>>().toEqualTypeOf<
      Result<{
        id: string;
        name: string;
        status: "lead" | "active" | "archived";
      }>
    >();
    expectTypeOf<Awaited<ReturnType<typeof shippingAddresses>>>().toEqualTypeOf<
      Result<
        {
          id: string;
          label: string;
          city: string | null;
          isPrimary: boolean;
        }[]
      >
    >();
  });
});
