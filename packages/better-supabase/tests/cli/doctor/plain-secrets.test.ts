import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type {
  CatalogColumn,
  CatalogTable,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { PLAIN_SECRET_RULES } from "../../../src/cli/doctor/plain-secrets.ts";
import { runRules } from "../../../src/cli/doctor/rules.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { snapshotFixture } from "../fixtures/library.ts";

const base = await parseSnapshot(snapshotFixture);

/** The fixture with `public.integrations` holding these columns. */
function withIntegrations(
  columns: Record<string, string>,
  triggers: CatalogTable["triggers"] = [],
): Snapshot {
  const catalog = structuredClone(toCatalog(base));

  const customers = catalog.tables.find(
    (table) => table.schema === "public" && table.name === "customers",
  )!;

  const [id] = customers.columns;

  const added = Object.entries(columns).map(([name, udt]): CatalogColumn => ({
    ...id!,
    name,
    udt,
    format: udt,
    typeSchema: "pg_catalog",
    hasDefault: false,
    default: null,
    identity: null,
  }));

  // SAFETY: a structured clone of the catalog, which the test owns.
  const tables = catalog.tables as CatalogTable[];
  tables.push({
    ...customers,
    id: 999_998,
    name: "integrations",
    columns: [id!, ...added],
    foreignKeys: [],
    indexes: [],
    policies: [],
    triggers,
  });

  // SAFETY: the catalog is plain data; fromCatalog reads it back.
  return fromCatalog(catalog);
}

const COLUMNS = {
  access_token: "text",
  client_secret: "jsonb",
  oauth_credentials: "jsonb",
  token_hash: "text",
  secret_id: "uuid",
  credential_ref: "jsonb",
  api_token: "bytea",
};

const run = (
  config: Parameters<typeof resolveConfig>[0],
  snapshot: Snapshot,
  sqlFiles: DoctorContext["sqlFiles"] = [],
) =>
  runRules(
    {
      config: resolveConfig(config, "/project"),
      snapshot,
      configToml: undefined,
      envFiles: [],
      gitignore: "",
      sources: [],
      sqlFiles,
    } satisfies DoctorContext,
    PLAIN_SECRET_RULES,
  );

const SEAL: CatalogTable["triggers"][number] = {
  name: "seal_secret_fields",
  timing: "before",
  events: ["insert", "update"],
  level: "row",
  function: "public.seal_secret_fields",
};

describe("BS352", () => {
  it("reports plain secret columns while field-encryption is installed", async () => {
    const findings = await run(
      { blocks: ["field-encryption"] },
      withIntegrations(COLUMNS),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "public.integrations.access_token",
      "public.integrations.client_secret",
      "public.integrations.oauth_credentials",
    ]);
    expect(findings[0]).toEqual(
      expect.objectContaining({
        code: "BS352",
        severity: "warning",
        object: { kind: "table", schema: "public", name: "integrations" },
        message: expect.stringContaining(
          "set `encrypted: true` on tables.integrations.columns.access_token",
        ),
      }),
    );
  });

  it("names both remedies when both blocks are installed", async () => {
    const [finding] = await run(
      { blocks: ["field-encryption", "credentials"] },
      withIntegrations({ access_token: "text" }),
    );

    expect(finding?.message).toContain(
      "field-encryption and credentials are installed",
    );
    expect(finding?.message).toContain(
      "keep a credential_ref jsonb in the row",
    );
  });

  it("skips a column marked encrypted in appTables", async () => {
    expect(
      await run(
        {
          blocks: ["field-encryption"],
          appTables: {
            integrations: {
              columns: { access_token: { type: "text", encrypted: true } },
            },
          },
        },
        withIntegrations({ access_token: "text" }),
      ),
    ).toEqual([]);
  });

  it("reports a header value named like a secret", async () => {
    const findings = await run(
      { blocks: ["field-encryption"] },
      withIntegrations({ auth_header_value: "text", header_name: "text" }),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "public.integrations.auth_header_value",
    ]);
  });

  it("skips a column an @bsb encrypted tag in the schema files marks", async () => {
    expect(
      await run(
        { blocks: ["field-encryption"] },
        withIntegrations({ access_token: "text" }),
        [
          {
            path: "supabase/schemas/integrations.sql",
            text: "comment on table public.integrations is '@bsb encrypted access_token=text';",
          },
        ],
      ),
    ).toEqual([]);
  });

  it("skips the columns a listed seal function assigns in a before trigger", async () => {
    const config = {
      blocks: ["field-encryption"],
      tooling: { doctor: { sealTriggers: ["public.seal_secret_fields"] } },
    } as const;

    expect(
      await run(
        config,
        withIntegrations({ access_token: "text", client_secret: "jsonb" }, [
          SEAL,
        ]),
      ),
    ).toEqual([]);

    const partial = await run(
      config,
      withIntegrations({ access_token: "text", client_secret: "jsonb" }, [
        { ...SEAL, fills: ["access_token"] },
      ]),
    );

    expect(partial.map((finding) => finding.target)).toEqual([
      "public.integrations.client_secret",
    ]);

    const unlisted = await run(
      { blocks: ["field-encryption"] },
      withIntegrations({ access_token: "text" }, [SEAL]),
    );

    expect(unlisted).toHaveLength(1);
  });

  it("stays quiet without a block that keeps secrets out of the row", async () => {
    expect(await run({}, withIntegrations(COLUMNS))).toEqual([]);
  });
});
