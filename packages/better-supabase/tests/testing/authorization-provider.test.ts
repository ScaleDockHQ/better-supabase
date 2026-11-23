import { describe, expect, it } from "vitest";

import type { AuthorizationProvider } from "../../src/config/index.ts";

import { testAuthorizationProvider } from "../../src/testing/authorization-provider.ts";
import { ConformanceError } from "../../src/testing/conformance.ts";
import {
  stubProvider,
  withProvider,
} from "../fixtures/authorization-provider.ts";

async function failures(provider: AuthorizationProvider): Promise<string[]> {
  const error = await testAuthorizationProvider(provider).then(
    () => undefined,
    (cause: unknown) => cause,
  );

  expect(error).toBeInstanceOf(ConformanceError);

  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => `${check.name}: ${check.message ?? ""}`);
}

describe("testAuthorizationProvider", () => {
  it("passes a provider that follows the contract", async () => {
    const report = await testAuthorizationProvider(stubProvider);
    expect(report.subject).toBe('AuthorizationProvider "stub"');
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(report.checks.map((check) => check.name)).toContain(
      "requires every function the templates call",
    );
  });

  it("matches {resource} in a template's function names to requires", async () => {
    const provider = withProvider({
      functions: {
        ...stubProvider.functions,
        rowsWith: "authz.{resource}_rows({permission}, {ids})",
      },
      requires: [
        ...stubProvider.requires,
        {
          function: "authz.file_node_rows",
          args: "text, text[]",
          role: "authenticated",
        },
      ],
    });

    const report = await testAuthorizationProvider(provider);

    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(
      await failures(
        withProvider({
          functions: {
            ...stubProvider.functions,
            rowsWith: "authz.{resource}_rows({permission}, {ids})",
          },
        }),
      ),
    ).toContainEqual(
      expect.stringContaining("calls authz.{resource}_rows, which requires"),
    );
  });

  it("refuses another API version and values that aren't JSON", async () => {
    expect(
      await failures({
        ...stubProvider,
        // @ts-expect-error -- the kit checks providers written in JavaScript too.
        apiVersion: 2,
      }),
    ).toEqual(["targets authorization API v1: apiVersion is 2"]);
    expect(
      await failures({
        ...stubProvider,
        name: "stub",
        // @ts-expect-error -- a function is not plain data.
        problems: [() => "x"],
      }),
    ).toEqual(["is plain JSON: it doesn't survive a JSON round trip"]);
  });

  it("refuses bad scopes", async () => {
    expect(
      await failures(
        withProvider({ scopes: [{ name: "Org", idType: "uuid" }] }),
      ),
    ).toContainEqual(
      expect.stringMatching(/scope "Org" is not lower snake case/),
    );
    expect(
      await failures(
        withProvider({
          scopes: [
            { name: "organization", idType: "uuid" },
            { name: "team", idType: "numeric", parent: "workspace" },
          ],
        }),
      ),
    ).toContainEqual(
      expect.stringMatching(
        /scope "team" has idType "numeric".*scope "team" has parent "workspace", which is not a scope/,
      ),
    );
    expect(await failures(withProvider({ tenantScope: "workspace" }))).toEqual([
      expect.stringMatching(/tenantScope "workspace" is not a scope/),
    ]);
    expect(
      await failures(
        withProvider({
          scopes: [
            { name: "organization", parent: "project" },
            { name: "project", idType: "uuid", parent: "organization" },
          ],
        }),
      ),
    ).toEqual([
      expect.stringMatching(
        /is its own ancestor \(a parent cycle\).*tenant scope "organization" has no idType/,
      ),
    ]);
  });

  it("refuses placeholders a template doesn't take, or a missing one", async () => {
    expect(
      await failures(
        withProvider({
          functions: {
            ...stubProvider.functions,
            isPlatform: "authz.is_platform({permission}, {tenant})",
            idsWithFor: "authz.ids_{scope}_for({permission})",
          },
        }),
      ),
    ).toEqual([expect.stringMatching(/functions\.isPlatform uses \{tenant\}/)]);
    expect(
      await failures(
        withProvider({
          functions: {
            ...stubProvider.functions,
            idsWithFor: "authz.ids_{scope}_for({permission})",
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(/functions\.idsWithFor doesn't use \{user\}/),
    ]);
  });

  it("refuses a template that calls a function requires doesn't list", async () => {
    expect(
      await failures(
        withProvider({
          requires: stubProvider.requires.filter(
            (entry) => entry.function !== "authz.ids_project",
          ),
        }),
      ),
    ).toEqual([
      expect.stringMatching(/functions\.idsWith calls authz\.ids_project/),
    ]);
  });

  it("refuses repeated permissions and unknown scopes", async () => {
    expect(
      await failures(
        withProvider({
          permissions: [
            { key: "documents.read", sqlComplete: true },
            { key: "documents.read", sqlComplete: true, scopes: ["team"] },
          ],
          memberships: [
            {
              table: "authz.team_members",
              userColumn: "user_id",
              scope: { value: "team" },
              idColumn: "team_id",
            },
          ],
          tokenHook: {
            ...stubProvider.tokenHook,
            function: "access_token_hook",
            budget: { claims: ["memberships"], bytes: 0 },
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(/permission "documents\.read" repeats/),
      expect.stringMatching(/authz\.team_members names unknown scope "team"/),
      expect.stringMatching(
        /tokenHook\.function "access_token_hook" is not schema\.name/,
      ),
    ]);
  });

  it("needs {scope}, {tenant} and {role} where the template must tell them apart", async () => {
    expect(
      await failures(
        withProvider({
          functions: {
            ...stubProvider.functions,
            idsWith: "authz.ids_organization({permission})",
            canAssign: "authz.can_assign({tenant}, 'member')",
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(
        /functions\.idsWith doesn't use \{scope\}, so it answers the same for every scope/,
      ),
    ]);
    expect(
      await failures(
        withProvider({
          functions: {
            ...stubProvider.functions,
            canAssign: "authz.can_assign({role})",
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(/functions\.canAssign doesn't use \{tenant\}/),
    ]);
  });

  it("refuses templates that aren't safe to inline", async () => {
    for (const [template, problem] of [
      ["authz.ids_{scope}({permission}); drop table x", /contains ";"/],
      ["authz.ids_{scope}({permission}) -- x", /contains "--"/],
      ["$$authz.ids_{scope}({permission})$$", /contains "\$\$"/],
      ["ids_{scope}({permission})", /calls ids_scope\(\) without a schema/],
      [
        "array(select unnest(authz.ids_{scope}({permission})))",
        /calls unnest\(\) without a schema/,
      ],
    ] as const) {
      expect(
        await failures(
          withProvider({
            functions: { ...stubProvider.functions, idsWith: template },
          }),
        ),
      ).toContainEqual(expect.stringMatching(problem));
    }

    expect(
      await testAuthorizationProvider(
        withProvider({
          functions: {
            ...stubProvider.functions,
            idsWith: "authz.ids_{scope}(coalesce({permission}, ';'))",
          },
        }),
      ),
    ).toBeDefined();
  });

  it("needs requires when the templates call functions", async () => {
    expect(await failures(withProvider({ requires: undefined }))).toEqual([
      expect.stringMatching(
        /the templates call functions, but requires is unset/,
      ),
    ]);
  });

  it("keeps owned and registered token hook claims apart", async () => {
    expect(
      await failures(
        withProvider({
          tokenHook: {
            ...stubProvider.tokenHook,
            ownedClaims: ["memberships", "features"],
            budget: { claims: ["features"], bytes: 512 },
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(
        /tokenHook registers "features", which ownedClaims also lists/,
      ),
    ]);
    expect(
      await failures(
        withProvider({
          tokenHook: {
            ...stubProvider.tokenHook,
            budget: { claims: ["permissions"], bytes: 512 },
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(/tokenHook\.budget counts "permissions"/),
    ]);
    expect(
      await failures(
        withProvider({
          tokenHook: {
            ...stubProvider.tokenHook,
            budget: { claims: ["features"], bytes: 512.5 },
          },
        }),
      ),
    ).toEqual([
      expect.stringMatching(
        /tokenHook\.budget\.bytes must be a positive integer/,
      ),
    ]);
    expect(
      await failures(
        withProvider({
          tokenHook: { ...stubProvider.tokenHook, ownedClaims: [] },
        }),
      ),
    ).toEqual([expect.stringMatching(/tokenHook\.ownedClaims is empty/)]);
  });

  it("checks the versions function and the claim its hook writes", async () => {
    const owned = withProvider({
      versions: { function: "stub.authz_version" },
      tokenHook: {
        ...stubProvider.tokenHook,
        ownedClaims: [...stubProvider.tokenHook.ownedClaims, "authz_ver"],
      },
    });

    const report = await testAuthorizationProvider(owned);
    expect(report.checks.map((check) => check.name)).toEqual(
      expect.arrayContaining([
        "names its versions function as schema.function",
        'writes "authz_ver" from its versions',
      ]),
    );

    expect(
      await failures(
        withProvider({ versions: { function: "Stub.Authz-Version" } }),
      ),
    ).toEqual([
      expect.stringMatching(/versions\.function "Stub\.Authz-Version"/),
      expect.stringMatching(/neither owns nor registers "authz_ver"/),
    ]);
  });

  it("checks the versions function in the database it is given", async () => {
    const calls: string[] = [];

    const postgres = {
      admin: {
        queryRaw: <R>(text: string): Promise<R[]> => {
          calls.push(text);

          const row = text.includes("pg_proc")
            ? { returns: "integer" }
            : { name: "receive" };

          // SAFETY: the kit reads only the column this stub fills.
          return Promise.resolve([row as R]);
        },
      },
      asUser: () => ({
        // SAFETY: the kit reads only `version`.
        queryRaw: <R>(): Promise<R[]> => Promise.resolve([{ version: 3 } as R]),
      }),
    };

    const error = await testAuthorizationProvider(
      withProvider({
        versions: { function: "stub.authz_version" },
        tokenHook: {
          ...stubProvider.tokenHook,
          ownedClaims: [...stubProvider.tokenHook.ownedClaims, "authz_ver"],
        },
      }),
      { postgres },
    ).then(
      () => undefined,
      (cause: unknown) => cause,
    );

    // SAFETY: the next line asserts the class.
    const failed = (error as ConformanceError).report.checks
      .filter((check) => !check.ok)
      .map((check) => check.message);

    expect(error).toBeInstanceOf(ConformanceError);
    expect(failed).toEqual([
      expect.stringMatching(/returns integer, not bigint/),
      expect.stringMatching(/read another user's version/),
    ]);
    expect(calls).toHaveLength(2);
  });

  it("checks suspension rows, role sources and deciding columns", async () => {
    expect(
      await failures(
        withProvider({
          suspension: {
            user: { table: "users", id: "id", disabledAt: "disabled_at" },
            tenant: { table: "authz.orgs", id: "id", status: "status" },
          },
          roleSources: [
            {
              table: "authz.memberships",
              role: {
                column: "role_id",
                through: { table: "roles", id: "id", column: "name" },
              },
            },
          ],
          decidingColumns: ["authz.memberships"],
        }),
      ),
    ).toEqual([
      expect.stringMatching(
        /suspension\.user\.table "users" is not schema\.table/,
      ),
      expect.stringMatching(
        /roleSources authz\.memberships reads roles from "roles"/,
      ),
      expect.stringMatching(
        /decidingColumns "authz\.memberships" is not schema\.table\.column/,
      ),
    ]);
  });

  it("accepts permissionsFor", async () => {
    const report = await testAuthorizationProvider(
      withProvider({
        functions: {
          ...stubProvider.functions,
          permissionsFor: "authz.permissions_for({user}, {tenant})",
        },
        requires: [
          ...stubProvider.requires,
          {
            function: "authz.permissions_for",
            args: "uuid, uuid",
            role: "authenticated",
          },
          {
            function: "authz.can_approve",
            args: "uuid, text",
            role: "authenticated",
          },
        ],
      }),
    );

    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("accepts isApprover with its placeholders and requires {tenant}", async () => {
    const isApprover = (template: string) =>
      withProvider({
        functions: { ...stubProvider.functions, isApprover: template },
        requires: [
          ...stubProvider.requires,
          {
            function: "authz.is_approver",
            args: "text, text, uuid",
            role: "authenticated",
          },
        ],
      });

    const report = await testAuthorizationProvider(
      isApprover("authz.is_approver({kind}, {subject}, {tenant})"),
    );

    expect(report.checks.every((check) => check.ok)).toBe(true);

    const withRequester = await testAuthorizationProvider(
      isApprover(
        "authz.is_approver({kind}, {subject}, {tenant}, ({requester})::text)",
      ),
    );

    expect(withRequester.checks.every((check) => check.ok)).toBe(true);
    expect(
      await failures(isApprover("authz.is_approver({kind}, {subject})")),
    ).toEqual([
      "templates use only their placeholders: functions.isApprover doesn't use {tenant}",
    ]);
    expect(
      await failures(isApprover("authz.is_approver({tool}, {tenant})")),
    ).toContainEqual(
      expect.stringMatching(/functions\.isApprover uses \{tool\}/),
    );
  });

  it("accepts managedUsers with or without {tenant}", async () => {
    const managedUsers = (template: string) =>
      withProvider({
        functions: { ...stubProvider.functions, managedUsers: template },
        requires: [
          ...stubProvider.requires,
          {
            function: "authz.managed_user_ids",
            args: "uuid",
            role: "authenticated",
          },
        ],
      });

    for (const template of [
      "authz.managed_user_ids({tenant})",
      "authz.managed_user_ids()",
    ]) {
      const report = await testAuthorizationProvider(managedUsers(template));
      expect(report.checks.every((check) => check.ok)).toBe(true);
    }

    expect(
      await failures(managedUsers("authz.managed_user_ids({user})")),
    ).toEqual([
      "templates use only their placeholders: functions.managedUsers uses {user}; it takes {tenant}",
    ]);
  });

  it("checks that operations name listed permissions", async () => {
    const report = await testAuthorizationProvider(
      withProvider({
        operations: {
          "mcp.tool.search_documents": { permission: "documents.read" },
        },
      }),
    );

    expect(report.checks.map((check) => check.name)).toContain(
      "operations name listed permissions",
    );
    expect(
      await failures(
        withProvider({
          operations: { "ai.tool.delete": { permission: "documents.delete" } },
        }),
      ),
    ).toEqual([
      `operations name listed permissions: operation "ai.tool.delete" needs "documents.delete", which permissions doesn't list`,
    ]);
  });

  it("checks approvals, the doctor command and action keys", async () => {
    expect(
      await failures(
        withProvider({
          operations: {
            "quote:send": {
              permission: "documents.write",
              approval: { steps: [] },
            },
          },
          doctor: { command: ["pnpm", ""] },
          actionKeys: { buckets: { files: { upload: "files.upload" } } },
        }),
      ),
    ).toEqual([
      'operation approvals list steps: operation "quote:send" has an approval without steps',
      "doctor names a command: doctor.command is empty",
      'actionKeys name listed permissions: actionKeys.buckets.files.upload needs "files.upload", which permissions doesn\'t list',
    ]);
    expect(
      await failures(
        withProvider({
          actionKeys: {
            blocks: { notes: { read: "documents.read", write: "" } },
          },
        }),
      ),
    ).toEqual([
      "actionKeys name listed permissions: actionKeys.blocks.notes.write names no permission",
    ]);
  });

  it("checks the tables the provider shares", async () => {
    expect(
      await failures(
        withProvider({
          tables: { "public.customers": { share: "tenant", permissions: [] } },
        }),
      ),
    ).toEqual([
      'shares tables per tenant only on listed permissions: tables.public.customers is share: "tenant" with no permissions: every member would read one entry whatever they hold',
    ]);
    expect(
      await failures(
        withProvider({
          tables: { "Bad Name": { share: "row", permissions: [] } },
        }),
      ),
    ).toEqual([
      'shares tables per tenant only on listed permissions: tables key "Bad Name" is not a table or schema.table name',
    ]);
  });

  it("accepts any action key when permissions are unlisted", async () => {
    const report = await testAuthorizationProvider(
      withProvider({
        permissions: undefined,
        operations: {
          "mcp.tool.x": {
            permission: "anything",
            approval: { steps: [{ role: "manager" }] },
          },
        },
        actionKeys: { topics: { chat: { listen: "anything" } } },
        doctor: { command: ["pnpm", "doctor"] },
      }),
    );

    expect(report.checks.map((check) => check.name)).toEqual(
      expect.arrayContaining([
        "actionKeys name listed permissions",
        "doctor names a command",
        "operation approvals list steps",
      ]),
    );
  });

  it("refuses memberships with an unknown scope value", async () => {
    expect(
      await failures(
        withProvider({
          memberships: [
            {
              table: "authz.memberships",
              userColumn: "user_id",
              scope: { value: "galaxy" },
              idColumn: "scope_id",
            },
          ],
        }),
      ),
    ).toEqual([
      'memberships name known scopes: authz.memberships names unknown scope "galaxy"',
    ]);
  });

  it("checks suspension columns and rows field by field", async () => {
    const cases = [
      [
        { user: "authz.users" },
        'suspension.user "authz.users" is not schema.table.column',
      ],
      [
        {
          tenant: {
            table: "authz.orgs",
            id: "org id",
            status: "s",
            active: ["a"],
          },
        },
        'suspension.tenant.id "org id" is not a column',
      ],
      [
        { tenant: { table: "authz.orgs", id: "id" } },
        "suspension.tenant sets neither disabledAt nor status",
      ],
      [
        {
          tenant: { table: "authz.orgs", id: "id", disabledAt: "disabled at" },
        },
        'suspension.tenant column "disabled at" is not a column',
      ],
      [
        { tenant: { table: "authz.orgs", id: "id", status: "status" } },
        "suspension.tenant needs status and active together",
      ],
    ] as const;

    for (const [suspension, message] of cases) {
      expect(await failures(withProvider({ suspension }))).toEqual([
        `suspension rows name a table, an id and a state column: ${message}`,
      ]);
    }
  });

  it("needs a sqlComplete key when the hook writes permissions", async () => {
    expect(
      await failures(
        withProvider({
          permissions: [{ key: "documents.read", sqlComplete: false }],
          tokenHook: {
            ...stubProvider.tokenHook,
            ownedClaims: ["memberships", "tenant_id", "permissions"],
          },
        }),
      ),
    ).toEqual([expect.stringMatching(/permissions marks no key sqlComplete/)]);
  });

  it("skips the version claim check without a token hook", async () => {
    const report = await testAuthorizationProvider(
      withProvider({
        versions: { function: "stub.authz_version" },
        tokenHook: undefined,
      }),
    ).catch((error: unknown) => (error as ConformanceError).report);

    expect(
      report.checks.find(
        (check) => check.name === 'writes "authz_ver" from its versions',
      )?.ok,
    ).toBe(true);
  });

  it("passes the database checks when a user can't read the version", async () => {
    const postgres = {
      admin: {
        queryRaw: <R>(text: string): Promise<R[]> =>
          // SAFETY: the kit reads only the column this stub fills.
          Promise.resolve([
            (text.includes("pg_proc")
              ? { returns: "bigint" }
              : { name: "receive" }) as R,
          ]),
      },
      asUser: () => ({
        queryRaw: (): Promise<never> => Promise.reject(new Error("denied")),
      }),
    };

    const report = await testAuthorizationProvider(
      withProvider({
        versions: { function: "stub.authz_version" },
        tokenHook: {
          ...stubProvider.tokenHook,
          ownedClaims: [...stubProvider.tokenHook.ownedClaims, "authz_ver"],
        },
      }),
      { postgres },
    );

    expect(report.checks.every((check) => check.ok)).toBe(true);
  });
});
