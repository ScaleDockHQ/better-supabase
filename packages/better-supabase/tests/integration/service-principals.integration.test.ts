import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ServicePrincipalAuthAdmin } from "../../src/blocks/service-principals/index.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { createServicePrincipals } from "../../src/blocks/service-principals/index.ts";
import {
  createWorkflowBuilder,
  sqlTransport,
  type WorkflowGraph,
} from "../../src/blocks/workflow-builder/index.ts";
import { moduleProvider } from "../fixtures/authorization-provider.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const CRM_GRAPH: WorkflowGraph = {
  nodes: [
    { id: "start", kind: "trigger" },
    { id: "lookup", kind: "step", step: "crm.lookup" },
  ],
  edges: [{ id: "e1", source: "start", target: "lookup" }],
};

// Members hold neither crm.read nor workflow rights; readers hold crm.read.
const LAYOUT: ModuleLayout = {
  modules: {
    access: {
      roles: {
        owner: ["*"],
        admin: [
          "organization.read",
          "members.*",
          "workflow.*",
          "service_principals.*",
        ],
        member: ["organization.read", "members.read"],
        reader: ["organization.read", "crm.read"],
      },
    },
  },
  accessProvider: {
    ...moduleProvider,
    operations: { "workflow.node.crm.lookup": { permission: "crm.read" } },
  },
};

describe.skipIf(!live)("service principals", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  /** An Auth admin that writes the user the way GoTrue would, inside the test's transaction. */
  function admin(s: BlockSession): ServicePrincipalAuthAdmin {
    return {
      createUser: async (attributes) => {
        const id = crypto.randomUUID();
        await s.client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at, banned_until, raw_app_meta_data)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now(),
             now() + $3::interval, $4)`,
          [
            id,
            attributes.email,
            attributes.ban_duration.replace("h", " hours"),
            attributes.app_metadata,
          ],
        );

        return { data: { user: { id } }, error: null };
      },
      deleteUser: async (id) => {
        await s.client.query("delete from auth.users where id = $1", [id]);

        return { error: null };
      },
    };
  }

  async function setUp(s: BlockSession) {
    await s.install(
      ["organizations", "workflow-builder", "service-principals"],
      LAYOUT,
    );
    const owner = await s.user("owner");
    const admin1 = await s.user("admin");
    const member = await s.user("member");
    const tenant = await s.organization(owner, { admin: admin1, member });
    await s.service();
    await createWorkflowBuilder({
      transport: sqlTransport(s.sql),
      steps: [{ name: "crm.lookup", title: "Look up a contact" }],
    })
      .steps.sync()
      .orThrow();

    const principals = createServicePrincipals({
      transport: sqlTransport(s.sql),
      admin: admin(s),
    });

    return { owner, admin: admin1, member, tenant, principals };
  }

  it("creates principals only as the service, for marked users and assignable roles", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { admin: admin1, member, tenant, principals } = await setUp(s);

      const created = await principals
        .create(tenant, "Automations", "member", {
          default: true,
          createdBy: admin1.id,
        })
        .orThrow();

      expect(created).toMatchObject({ role: "member", isDefault: true });
      expect(await principals.defaultFor(tenant).orThrow()).toBe(created.id);
      expect(
        await s.value<string>(
          "(select role from better_supabase.memberships where organization_id = $1 and user_id = $2)",
          [tenant, created.id],
        ),
      ).toBe("member");

      const users = await s.value<number>(
        "(select count(*)::int from auth.users)",
      );

      const refused = await principals.create(tenant, "Bot", "admin", {
        createdBy: member.id,
      });

      expect(!refused.ok && refused.error.hint).toBe(
        "SERVICE_PRINCIPAL_FORBIDDEN",
      );
      expect(
        await s.value<number>("(select count(*)::int from auth.users)"),
      ).toBe(users);

      const real = await s.user("real");

      const takeover = await sqlTransport(s.sql)
        .call("better_supabase", "register_service_principal", {
          principal: real.id,
          tenant,
          name: "Takeover",
          role: "member",
          is_default: false,
          created_by: null,
        })
        .then(
          () => undefined,
          (error: unknown) => error,
        );

      expect(String(takeover)).toContain("not a service principal");

      await s.asRole(admin1);

      const listed = await createServicePrincipals({
        transport: sqlTransport(s.sql),
        admin: admin(s),
      })
        .list(tenant)
        .orThrow();

      expect(listed.map((row) => row.name)).toEqual(["Automations"]);

      const direct = await createServicePrincipals({
        transport: sqlTransport(s.sql),
        admin: admin(s),
      }).setRole(created.id, "admin");

      expect(!direct.ok && direct.error.kind).toBe("forbidden");
    } finally {
      await s.close();
    }
  });

  it("runs an organization-owned version as the default principal, limited to its role", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { tenant, principals } = await setUp(s);
      const builder = createWorkflowBuilder({ transport: sqlTransport(s.sql) });

      const definition = await builder.definitions
        .save({ tenant, slug: "nightly", name: "Nightly" })
        .orThrow();

      const draft = await builder.versions
        .save(definition.id, CRM_GRAPH)
        .orThrow();

      await builder.versions.publish(draft.id).orThrow();

      const none = await builder.versions.runAs(draft.id);
      expect(!none.ok && none.error.message).toContain(
        "no default service principal",
      );

      const principal = await principals
        .create(tenant, "Automations", "member", { default: true })
        .orThrow();

      const limited = await builder.versions.runAs(draft.id);
      expect(!limited.ok && limited.error).toMatchObject({
        kind: "forbidden",
        hint: "WORKFLOW_PUBLISHER_REVOKED",
      });
      expect(!limited.ok && limited.error.message).toContain(
        "service principal no longer holds crm.read",
      );

      await principals.setRole(principal.id, "reader").orThrow();
      expect(await builder.versions.runAs(draft.id).orThrow()).toEqual({
        role: "authenticated",
        sub: principal.id,
        tenant_id: tenant,
        bs_permission_cap: ["crm.read"],
      });
      expect(
        await s.value<boolean>(
          "better_supabase.member_can($1, $2, 'crm.read')",
          [principal.id, tenant],
        ),
      ).toBe(true);
      expect(
        await s.value<boolean>(
          "better_supabase.member_can($1, $2, 'workflow.publish')",
          [principal.id, tenant],
        ),
      ).toBe(false);

      expect(await principals.disable(principal.id).orThrow()).toBe(true);
      const disabled = await builder.versions.runAs(draft.id);
      expect(!disabled.ok && disabled.error.message).toContain(
        "no default service principal",
      );
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.memberships where user_id = $1)",
          [principal.id],
        ),
      ).toBe(0);
    } finally {
      await s.close();
    }
  });
});
