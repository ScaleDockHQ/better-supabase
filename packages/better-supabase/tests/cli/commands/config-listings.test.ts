import { describe, expect, it } from "vitest";

import type {
  Catalog,
  CatalogFunction,
} from "../../../src/cli/introspect/types.ts";

import { shareableReport } from "../../../src/cli/commands/config-listings.ts";
import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { withProvider } from "../../fixtures/authorization-provider.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const base = await parseSnapshot(fixture);

const payload = (
  name: string,
  rest: Partial<CatalogFunction> = {},
): CatalogFunction => ({
  schema: "public",
  name,
  signature: "",
  args: [],
  returnsTable: null,
  returns: "jsonb",
  returnsRelation: null,
  returnsSet: false,
  volatility: "stable",
  securityDefiner: false,
  language: "sql",
  searchPath: null,
  ...rest,
});

describe("config functions --shareable", () => {
  const copy = structuredClone(toCatalog(base)) as {
    -readonly [K in keyof Catalog]: Catalog[K];
  };

  const [table] = copy.tables;
  const reads = `select coalesce(jsonb_agg(c), '[]') from ${table!.schema}.${table!.name} c`;

  copy.functions = [
    ...copy.functions,
    payload("customer_payload"),
    payload("order_payload", { securityDefiner: true }),
    payload("customer_lookup"),
  ];

  const catalog = fromCatalog(copy);

  const snapshot = {
    ...catalog,
    extras: {
      ...catalog.extras,
      functionSources: {
        "public.customer_payload": reads,
        "public.order_payload": reads,
        "public.customer_lookup": reads,
      },
    },
  };

  const config = resolveConfig(
    {
      auth: {
        authorization: withProvider({
          tables: {
            [table!.name]: { share: "tenant", permissions: ["customer.read"] },
          },
        }),
      },
      blocks: ["memberships", "permissions"],
    },
    "/project",
  );

  it("checks every match and gives each verdict with its reasons", async () => {
    const result = await shareableReport(config, snapshot, "public.*_payload");

    expect(result.code).toBe(0);
    expect(result.output).toContain(
      `public.customer_payload: shareable once sharedFunctions lists it (reads ${table!.schema}.${table!.name})`,
    );
    expect(result.output).toContain("public.order_payload: can't be shared");
    expect(result.output).toContain("  - it is security definer");
    expect(result.output).not.toContain("customer_lookup");
    expect(result.output).toContain("1 of 2 can be shared.");
  });

  it("reads a bare glob as public and says when nothing matches", async () => {
    const bare = await shareableReport(config, snapshot, "*_payload");
    expect(bare.output).toContain("1 of 2 can be shared.");

    const none = await shareableReport(config, snapshot, "api.*");
    expect(none.output).toBe("No function matches api.*.");
  });

  it("fails without an authorization provider", async () => {
    const result = await shareableReport(
      resolveConfig({}, "/project"),
      snapshot,
      "public.*",
    );

    expect(result.code).toBe(1);
  });
});
