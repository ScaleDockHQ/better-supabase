import { describe, expect, it } from "vitest";

import { restatedEntries } from "../../src/config/restated.ts";

const tables = {
  memberships: {
    columns: {
      tenant: "tenant_id",
      user: "user_id",
      lastUsedAt: "last_used_at",
    },
    optional: ["lastUsedAt"],
  },
};

const input = (blocks: object, extra: object = {}) => ({
  // SAFETY: the fixtures set only the keys restatedEntries reads.
  blocks: blocks as never,
  defaultColumns: () => tables,
  ...extra,
});

const paths = (entries: ReturnType<typeof restatedEntries>) =>
  entries.map((entry) => `${entry.kind}:${entry.path}`);

describe("restatedEntries", () => {
  it("reports an identity mapping of an optional column", () => {
    expect(
      paths(
        restatedEntries(
          input({
            memberships: {
              columns: { memberships: { lastUsedAt: "last_used_at" } },
            },
          }),
        ),
      ),
    ).toEqual(["identity:blocks.memberships.columns.memberships.lastUsedAt"]);
  });

  it("keeps a required identity mapping and a renamed column", () => {
    expect(
      restatedEntries(
        input({
          memberships: {
            columns: {
              memberships: { lastUsedAt: "last_used_at", user: "uid" },
            },
            requiredColumns: { memberships: ["lastUsedAt"] },
          },
        }),
      ),
    ).toEqual([]);
  });

  it("reports a null for a column the view lacks", () => {
    expect(
      paths(
        restatedEntries(
          input(
            {},
            {
              nulls: [
                {
                  block: "tags",
                  logical: "tags",
                  column: "rank",
                  name: "rank",
                  view: "public.tags",
                },
              ],
            },
          ),
        ),
      ),
    ).toEqual(["null:blocks.tags.columns.tags.rank"]);
  });

  it("reports empty maps", () => {
    expect(
      paths(
        restatedEntries(input({ tags: { values: {}, columns: { tags: {} } } })),
      ),
    ).toEqual(["empty:blocks.tags.values", "empty:blocks.tags.columns.tags"]);
  });

  it("reports a tenant column equal to sql.tenantColumn only", () => {
    const blocks = {
      teams: { columns: { memberships: { tenant: "org_id" } } },
      tags: { columns: { memberships: { tenant: "account_id" } } },
    };

    expect(
      paths(restatedEntries(input(blocks, { sqlTenantColumn: "org_id" }))),
    ).toEqual(["tenant:blocks.teams.columns.memberships.tenant"]);
  });

  it("reports the claims hook equal to the provider's token hook", () => {
    const provider = {
      name: "stub",
      tokenHook: { function: "authz.access_token_hook" },
      // SAFETY: only the fields restatedEntries reads are set.
    } as never;

    expect(
      paths(
        restatedEntries(
          input(
            {
              impersonation: {
                options: { claimsHook: "authz.access_token_hook" },
              },
            },
            { provider },
          ),
        ),
      ),
    ).toEqual(["provider:blocks.impersonation.options.claimsHook"]);
  });
});
