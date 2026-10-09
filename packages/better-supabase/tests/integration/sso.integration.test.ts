import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createSso,
  createSsoAdmin,
  scimHandler,
  sqlTransport,
} from "../../src/blocks/sso/index.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const domain = () => `acme-${crypto.randomUUID().slice(0, 8)}.test`;

const roleOf = (s: BlockSession, tenant: string, user: string) =>
  s.value<string | null>(
    "(select role from better_supabase.memberships where organization_id = $1 and user_id = $2)",
    [tenant, user],
  );

/** A domain verified for the owner's organization. */
async function verified(
  s: BlockSession,
  tenant: string,
  owner: { id: string; email: string },
  name: string,
) {
  await s.as(owner);
  const row = await s.value<{ id: string }>(
    "better_supabase.add_organization_domain($1, $2)",
    [tenant, name],
  );
  await s.service();
  await s.value("better_supabase.verify_organization_domain($1, $2)", [
    row.id,
    owner.id,
  ]);
  return row.id;
}

describe.skipIf(!live)("sso", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("claims and verifies domains for one organization", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "outbox", "sso"]);
      const name = domain();
      const owner = await s.user("owner", name);
      const member = await s.user("member", name);
      const tenant = await s.organization(owner, { member });

      await s.as(owner);
      const added = await s.value<{
        id: string;
        record: { name: string; value: string };
        verification_token?: string;
      }>("better_supabase.add_organization_domain($1, $2)", [
        tenant,
        ` ${name.toUpperCase()}. `,
      ]);
      expect(added.record.name).toBe(`_better-supabase.${name}`);
      expect(added.record.value).toMatch(
        /^better-supabase-domain-verification=[0-9a-f]{32}$/,
      );
      expect(added.verification_token).toBeUndefined();
      expect(
        await s.hint(
          "better_supabase.add_organization_domain($1, 'not a domain')",
          [tenant],
        ),
      ).toBe("SSO_DOMAIN_INVALID");
      expect(
        await s.hint(
          "better_supabase.update_organization_domain($1, null, true)",
          [added.id],
        ),
      ).toBe("SSO_DOMAIN_NOT_VERIFIED");
      await s.as(member);
      expect(
        await s.hint("better_supabase.add_organization_domain($1, $2)", [
          tenant,
          name,
        ]),
      ).toBe("SSO_FORBIDDEN");
      expect(
        await s.hint("better_supabase.verify_organization_domain($1)", [
          added.id,
        ]),
      ).toBe("SSO_FORBIDDEN");

      await s.service();
      expect(
        await s.hint("better_supabase.verify_organization_domain($1, $2)", [
          added.id,
          member.id,
        ]),
      ).toBe("SSO_DOMAIN_NOT_FOUND");
      const resolved: string[] = [];
      const admin = createSsoAdmin({
        transport: sqlTransport(s.sql),
        resolver: (record) => {
          resolved.push(record);
          return Promise.resolve([added.record.value]);
        },
      });
      const done = await admin
        .verifyDomain(added.id, { actorId: owner.id })
        .orThrow();
      expect(done.verifiedAt).toBeDefined();
      expect(resolved).toEqual([`_better-supabase.${name}`]);
      expect(
        await s.rows<{ type: string }>(
          "select type from better_supabase.outbox_events where organization_id = $1 and type like 'organization.domain%'",
          [tenant],
        ),
      ).toEqual([
        { type: "organization.domain_added" },
        { type: "organization.domain_verified" },
      ]);

      const rival = await s.user("rival");
      const other = await s.organization(rival);
      await s.as(rival);
      const claim = await s.value<{ id: string }>(
        "better_supabase.add_organization_domain($1, $2)",
        [other, name],
      );
      await s.service();
      expect(
        await s.hint("better_supabase.verify_organization_domain($1)", [
          claim.id,
        ]),
      ).toBe("SSO_DOMAIN_TAKEN");

      await s.as(owner);
      const sso = createSso({ transport: sqlTransport(s.sql) });
      const [listed] = await sso.domains(tenant).orThrow();
      expect(listed).toMatchObject({ domain: name, enforceSso: false });
      expect(
        await sso
          .updateDomain(added.id, { autoJoinRole: "owner" })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("SSO_ROLE_INVALID");
      expect(await sso.removeDomain(claim.id).orThrow()).toBe(false);
    } finally {
      await s.close();
    }
  });

  it("auto-joins confirmed users and enforces SAML in the access token hook", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "outbox", "sso"]);
      const name = domain();
      const owner = await s.user("owner", name);
      const tenant = await s.organization(owner);
      const id = await verified(s, tenant, owner, name);
      await s.as(owner);
      await s.value(
        "better_supabase.update_organization_domain($1, 'member', true)",
        [id],
      );

      await s.service();
      const joined = await s.user("new", name);
      expect(await roleOf(s, tenant, joined.id)).toBe("member");
      const outsider = await s.user("outsider");
      expect(await roleOf(s, tenant, outsider.id)).toBeNull();

      const pendingId = crypto.randomUUID();
      await s.rows(
        `insert into auth.users (id, email, aud, role, instance_id) values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')`,
        [pendingId, `pending@${name}`],
      );
      expect(await roleOf(s, tenant, pendingId)).toBeNull();
      await s.rows(
        "update auth.users set email_confirmed_at = now() where id = $1",
        [pendingId],
      );
      expect(await roleOf(s, tenant, pendingId)).toBe("member");

      const check = (user: string, extra: object) =>
        s.value<Record<string, unknown>>(
          "better_supabase.sso_access_token_check($1)",
          [{ user_id: user, claims: { sub: user }, ...extra }],
        );
      expect(
        await check(joined.id, { authentication_method: "password" }),
      ).toEqual({
        error: {
          http_code: 403,
          message: "Sign in with your organization's single sign-on",
        },
      });
      expect(
        await check(joined.id, {
          claims: { amr: [{ method: "sso/saml", timestamp: 1 }] },
        }),
      ).toEqual({
        user_id: joined.id,
        claims: { amr: [{ method: "sso/saml", timestamp: 1 }] },
      });
      expect(
        await check(outsider.id, { authentication_method: "password" }),
      ).toMatchObject({
        user_id: outsider.id,
      });

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and type = 'organization.member_added'",
        [tenant],
      );
      expect(events).toHaveLength(2);
    } finally {
      await s.close();
    }
  });

  it("records SAML providers only for verified domains", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "sso"]);
      const name = domain();
      const owner = await s.user("owner", name);
      const tenant = await s.organization(owner);
      const id = await verified(s, tenant, owner, name);
      const provider = crypto.randomUUID();

      await s.service();
      expect(
        await s.hint("better_supabase.register_sso_provider($1, $2, $3)", [
          tenant,
          provider,
          ["other.test"],
        ]),
      ).toBe("SSO_DOMAIN_NOT_VERIFIED");
      await s.value(
        "better_supabase.register_sso_provider($1, $2, $3, 'https://idp.test/m', $4)",
        [tenant, provider, [name.toUpperCase()], owner.id],
      );
      await s.as("anon");
      expect(
        await s.value("better_supabase.sso_domain_for($1)", [
          `someone@${name.toUpperCase()}`,
        ]),
      ).toEqual({
        domain: name,
        organizationId: tenant,
        providerId: provider,
        enforceSso: false,
      });
      expect(
        await s.value("better_supabase.sso_domain_for('a@nowhere.test')"),
      ).toBeNull();

      await s.as(owner);
      expect(
        await s.hint("better_supabase.remove_organization_domain($1)", [id]),
      ).toBe("SSO_DOMAIN_IN_USE");
      const sso = createSso({ transport: sqlTransport(s.sql) });
      expect((await sso.providers(tenant).orThrow()).map((p) => p.id)).toEqual([
        provider,
      ]);

      await s.service();
      const admin = createSsoAdmin({
        transport: sqlTransport(s.sql),
        auth: {
          url: "https://project.test",
          secretKey: "k",
          fetch: () => Promise.resolve(new Response(null, { status: 404 })),
        },
      });
      const removed = await admin
        .removeSamlProvider(provider, { actorId: owner.id })
        .orThrow();
      expect(removed?.domains).toEqual([name]);
      expect(
        await s.value("better_supabase.sso_provider($1)", [provider]),
      ).toBeNull();
    } finally {
      await s.close();
    }
  });

  it("provisions memberships through SCIM and keeps them to the organization", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "outbox", "sso"]);
      const name = domain();
      const owner = await s.user("owner", name);
      const tenant = await s.organization(owner);
      await verified(s, tenant, owner, name);
      const outsider = await s.user("outsider");

      await s.service();
      const handler = scimHandler({
        transport: sqlTransport(s.sql),
        keys: {
          verify: () =>
            AsyncResult.from(async () =>
              ok({
                status: "ok" as const,
                key: {
                  id: "k",
                  organizationId: tenant,
                  userId: undefined,
                  name: "idp",
                  prefix: "bs",
                  publicId: "p",
                  scopes: ["scim"],
                } as never,
              }),
            ),
        },
        basePath: "/scim/v2",
      });
      const send = async (method: string, path: string, body?: unknown) => {
        const response = await handler(
          new Request(`https://app.test/scim/v2${path}`, {
            method,
            headers: {
              authorization: "Bearer t",
              "content-type": "application/scim+json",
            },
            ...(body === undefined ? {} : { body: JSON.stringify(body) }),
          }),
        );
        const text = await response.text();
        return {
          status: response.status,
          body: (text ? JSON.parse(text) : {}) as Record<string, unknown>,
        };
      };
      const USER = "urn:ietf:params:scim:schemas:core:2.0:User";
      const PATCH = "urn:ietf:params:scim:api:messages:2.0:PatchOp";

      const waiting = await send("POST", "/Users", {
        schemas: [USER],
        userName: `ada@${name}`,
        emails: [{ value: `Ada@${name}`, primary: true }],
      });
      expect(waiting.status).toBe(201);
      const adaId = crypto.randomUUID();
      await s.rows(
        `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at) values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
        [adaId, `ada@${name}`],
      );
      expect(await roleOf(s, tenant, adaId)).toBe("member");

      const foreign = await send("POST", "/Users", {
        schemas: [USER],
        userName: outsider.email,
        emails: [{ value: outsider.email }],
      });
      expect(foreign.status).toBe(201);
      expect(await roleOf(s, tenant, outsider.id)).toBeNull();

      expect(
        (
          await send("POST", "/Users", {
            schemas: [USER],
            userName: `ADA@${name}`,
          })
        ).status,
      ).toBe(409);

      const group = await send("POST", "/Groups", {
        schemas: ["urn:ietf:params:scim:schemas:core:2.0:Group"],
        displayName: "Admin",
        members: [{ value: waiting.body["id"] }],
      });
      expect(group.status).toBe(201);
      expect(await roleOf(s, tenant, adaId)).toBe("admin");
      const user = await send("GET", `/Users/${String(waiting.body["id"])}`);
      expect(user.body["groups"]).toMatchObject([
        { value: group.body["id"], display: "Admin" },
      ]);

      await send("PATCH", `/Groups/${String(group.body["id"])}`, {
        schemas: [PATCH],
        Operations: [
          {
            op: "remove",
            path: `members[value eq "${String(waiting.body["id"])}"]`,
          },
        ],
      });
      expect(await roleOf(s, tenant, adaId)).toBe("member");

      const deactivated = await send(
        "PATCH",
        `/Users/${String(waiting.body["id"])}`,
        {
          schemas: [PATCH],
          Operations: [{ op: "replace", path: "active", value: false }],
        },
      );
      expect(deactivated.body["active"]).toBe(false);
      expect(await roleOf(s, tenant, adaId)).toBeNull();
      await send("PATCH", `/Users/${String(waiting.body["id"])}`, {
        schemas: [PATCH],
        Operations: [{ op: "replace", path: "active", value: true }],
      });
      expect(await roleOf(s, tenant, adaId)).toBe("member");

      const ownerScim = await send("POST", "/Users", {
        schemas: [USER],
        userName: owner.email,
        active: false,
      });
      expect(ownerScim.status).toBe(201);
      expect(await roleOf(s, tenant, owner.id)).toBe("owner");

      expect(
        (await send("DELETE", `/Users/${String(waiting.body["id"])}`)).status,
      ).toBe(204);
      expect(await roleOf(s, tenant, adaId)).toBeNull();
      expect(
        (await send("GET", `/Users/${String(waiting.body["id"])}`)).status,
      ).toBe(404);
      expect(
        (await send("DELETE", `/Groups/${String(group.body["id"])}`)).status,
      ).toBe(204);

      await s.as(owner);
      expect(
        await s.hint("better_supabase.scim_list_users($1)", [tenant]),
      ).toBe("SSO_FORBIDDEN");
    } finally {
      await s.close();
    }
  });
});
