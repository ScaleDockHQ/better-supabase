import { describe, expectTypeOf, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { defineSeed, defineTenantSeed } from "../../src/testing/seed.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

describe("seed types", () => {
  it("keeps fixture names and checks rows against Insert types", () => {
    const seed = defineSeed(betterSupabase, {
      customers: {
        acme: {
          id: "c1",
          organizationId: "o1",
          name: "Acme",
          status: "active",
        },
      },
    });

    expectTypeOf(seed.rows.customers.acme.id).toEqualTypeOf<"c1">();

    defineSeed(betterSupabase, {
      // @ts-expect-error name is required
      customers: { acme: { organizationId: "o1" } },
    });
    defineSeed(betterSupabase, {
      customers: {
        acme: {
          organizationId: "o1",
          name: "Acme",
          // @ts-expect-error status is a union
          status: "nope",
        },
      },
    });
    defineSeed(betterSupabase, {
      // @ts-expect-error unknown column
      customers: { acme: { organizationId: "o1", name: "Acme", nope: 1 } },
    });
    defineSeed(betterSupabase, {
      // @ts-expect-error unknown table
      nope: {},
    });
  });

  it("checks tenant seed rows against Insert types", () => {
    defineTenantSeed(betterSupabase, (tenant) => ({
      customers: {
        demo: { organizationId: tenant.id, name: "Demo", status: "lead" },
      },
    }));
    defineTenantSeed(betterSupabase, (tenant) => ({
      customers: {
        demo: {
          organizationId: tenant.id,
          name: "Demo",
          // @ts-expect-error status is a union
          status: "nope",
        },
      },
    }));
    defineTenantSeed(betterSupabase, (tenant) => ({
      customers: {
        // @ts-expect-error unknown column
        demo: { organizationId: tenant.id, name: "Demo", nope: 1 },
      },
    }));
  });
});
