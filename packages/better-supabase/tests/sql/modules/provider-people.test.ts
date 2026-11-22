import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";
import type { BlockSqlAccessProvider } from "../../../src/sql/module-types.ts";

import { modulePermissionKeys } from "../../../src/sql/introspect.ts";
import { withProviderKeys } from "../../../src/sql/layout.ts";
import { renderBlocks } from "../app-columns.ts";

const provider = (
  functions: Record<string, string> = {},
): BlockSqlAccessProvider => ({
  name: "test",
  scope: "organization",
  idType: "uuid",
  functions: {
    idsWith: "authz.ids_with({permission})",
    isPlatform: "authz.is_platform({permission})",
    holdersOf: "authz.holders_of({permission}, {tenant})",
    ...functions,
  },
});

const MODULES: AnyBlocksConfig = { permissions: { model: "provider" } };

const sqlOf = (
  module: string,
  layout: Parameters<typeof renderBlocks>[1],
  modules: readonly string[] = ["permissions", "approvals", module],
  all = true,
): string =>
  renderBlocks(modules, layout)
    .filter((file) => all || file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("provider approverFor", () => {
  const withApprover = provider({
    approverFor: "authz.approvers_for({kind}, {id})",
  });

  it("lets the provider's set decide a leave request", () => {
    const sql = sqlOf("leave", {
      modules: MODULES,
      accessProvider: withApprover,
    });

    expect(sql).toContain("authz.approvers_for('leave',");
    expect(sql).toContain("as t(u)");
  });

  it("renders nothing without the template or without {id}", () => {
    expect(
      sqlOf("leave", { modules: MODULES, accessProvider: provider() }),
    ).not.toContain("approvers_for");
    expect(
      sqlOf("leave", {
        modules: MODULES,
        accessProvider: provider({ approverFor: "authz.approvers()" }),
      }),
    ).not.toContain("authz.approvers()");
  });

  it("lets the decider option win", () => {
    const sql = sqlOf("leave", {
      modules: {
        permissions: { model: "provider" },
        leave: { options: { decider: "app.may_decide" } },
      },
      accessProvider: withApprover,
    });

    expect(sql).toMatch(/may_decide/);
    expect(sql).not.toContain("approvers_for");
  });

  it("is read by time entries", () => {
    for (const [module, kind] of [["time-entries", "time-entry"]] as const) {
      expect(
        sqlOf(module, { modules: MODULES, accessProvider: withApprover }),
      ).toContain(`authz.approvers_for('${kind}',`);
    }
  });
});

describe("provider managedUsers", () => {
  it("counts the people the caller manages as their reports", () => {
    const sql = sqlOf(
      "leave",
      {
        modules: MODULES,
        accessProvider: provider({ managedUsers: "authz.managed({tenant})" }),
      },
      ["permissions", "approvals", "leave"],
    );

    expect(sql).toContain("authz.managed(");
  });
});

describe("provider operation approval floors", () => {
  const steps = [{ approvers: { permission: "invoice.approve" } }];

  it("adds a floor for an operation without a policy entry", () => {
    const sql = sqlOf("approvals", {
      modules: MODULES,
      accessProvider: provider(),
      providerApprovals: { "invoice:send": { steps } },
    });

    expect(sql).toContain("invoice:send");
  });

  it("lets options.policies win", () => {
    const sql = sqlOf("approvals", {
      modules: {
        permissions: { model: "provider" },
        approvals: {
          options: {
            policies: {
              invoice: {
                send: { steps: [{ approvers: { permission: "own.key" } }] },
              },
            },
          },
        },
      },
      accessProvider: provider(),
      providerApprovals: { "invoice:send": { steps } },
    });

    expect(sql).toContain("own.key");
    expect(sql).not.toContain("invoice.approve");
  });
});

describe("provider actionKeys", () => {
  it("uses the provider's key for a block action and lets config win", () => {
    const keys = (layoutKeys: Record<string, string>) =>
      modulePermissionKeys(
        { permissions: { model: "provider" }, ...({} as AnyBlocksConfig) },
        ["permissions", "audit"],
        undefined,
        { blocks: { audit: layoutKeys } },
      ).map((entry) => entry.key);

    expect(keys({ read: "custom.audit.read" })).toContain("custom.audit.read");
  });

  it("merges recordTypes keys under the config's own", () => {
    const merged = withProviderKeys(
      { note: { table: "notes", permissions: { read: "mine.read" } } },
      { recordTypes: { note: { read: "p.read", update: "p.update" } } },
    );

    expect(merged["note"]?.permissions).toEqual({
      read: "mine.read",
      update: "p.update",
    });
  });
});
