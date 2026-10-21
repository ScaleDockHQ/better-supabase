import { beforeAll, describe, expect, it } from "vitest";

import type {
  BlockTransport,
  MarketplaceResourceHooks,
  PartnerApiOptions,
} from "../../../src/blocks/vercel-marketplace/index.ts";
import type { Jwks } from "../../../src/core/jws.ts";

import { createVercelMarketplace } from "../../../src/blocks/vercel-marketplace/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const encoder = new TextEncoder();
const BASE = "https://app.test/api/vercel/v1";

const b64 = (value: string | Uint8Array): string =>
  Buffer.from(value).toString("base64url");

let privateKey: CryptoKey;
let jwks: Jwks;

beforeAll(async () => {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );

  const jwk = await crypto.subtle.exportKey("jwk", pair.publicKey);

  privateKey = pair.privateKey;
  jwks = {
    keys: [
      {
        kty: "RSA",
        n: jwk.n ?? "",
        e: jwk.e ?? "",
        kid: "k1",
        alg: "RS256",
        use: "sig",
      },
    ],
  };
});

async function oidc(extra: Record<string, unknown> = {}): Promise<string> {
  const header = b64(JSON.stringify({ alg: "RS256", kid: "k1" }));

  const body = b64(
    JSON.stringify({
      iss: "https://marketplace.vercel.com",
      aud: "oac_1",
      exp: Math.floor(Date.now() / 1000) + 600,
      installation_id: "icfg_1",
      account_id: "team_1",
      user_id: "user_1",
      ...extra,
    }),
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    privateKey,
    encoder.encode(`${header}.${body}`),
  );

  return `${header}.${body}.${b64(new Uint8Array(signature))}`;
}

const installationRow = (extra: Record<string, unknown> = {}) => ({
  id: "i1",
  configuration_id: "icfg_1",
  team_id: "team_1",
  status: "active",
  metadata: {},
  ...extra,
});

const resourceRow = (extra: Record<string, unknown> = {}) => ({
  id: "r1",
  installation_id: "i1",
  external_id: "res_1",
  name: "db",
  plan_id: "free",
  status: "ready",
  metadata: { productId: "prod_1", vercel: { region: "fra1" } },
  secret_refs: [],
  ...extra,
});

type Results = Record<string, unknown>;

function setup(
  results: Results,
  options: Partial<PartnerApiOptions> & {
    readonly resources?: MarketplaceResourceHooks;
  } = {},
) {
  const calls: [string, Record<string, unknown>][] = [];

  const transport: BlockTransport = {
    call(_schema, fn, args) {
      calls.push([fn, { ...args }]);

      const result = results[fn];

      return Promise.resolve(
        typeof result === "function" ? result({ ...args }) : (result ?? null),
      );
    },
  };

  const marketplace = createVercelMarketplace({
    transport,
    clientId: "oac_1",
    clientSecret: "secret",
    jwks,
  });

  const handler = marketplace.partnerApi({
    resources: {
      provision: () =>
        Promise.resolve({
          tenant: "org_1",
          tenantCreated: true,
          secrets: [
            {
              name: "APP_API_KEY",
              value: "sk_live",
              ref: "key_1",
              environmentOverrides: { preview: "sk_preview" },
            },
          ],
        }),
    },
    ...options,
  });

  const send = async (
    method: string,
    path: string,
    body?: unknown,
    token?: string | null,
  ): Promise<Response> => {
    const bearer = token === undefined ? await oidc() : token;

    return handler(
      new Request(`${BASE}${path}`, {
        method,
        headers: bearer === null ? {} : { authorization: `Bearer ${bearer}` },
        ...(body === undefined
          ? {}
          : { body: typeof body === "string" ? body : JSON.stringify(body) }),
      }),
    );
  };

  return { calls, send, names: () => calls.map(([name]) => name) };
}

describe("partnerApi", () => {
  describe("OIDC", () => {
    it("answers 401 without a bearer token or with a token it cannot verify", async () => {
      const { send, calls } = setup({});

      const missing = await send(
        "GET",
        "/installations/icfg_1",
        undefined,
        null,
      );

      const garbage = await send(
        "GET",
        "/installations/icfg_1",
        undefined,
        "a.b.c",
      );

      expect(missing.status).toBe(401);
      expect(missing.headers.get("content-type")).toContain(
        "application/problem+json",
      );
      expect(garbage.status).toBe(401);
      expect(calls).toEqual([]);
    });

    it("answers 403 for a wrong audience, issuer or an expired token", async () => {
      for (const extra of [
        { aud: "oac_other" },
        { iss: "https://evil.test" },
        { exp: Math.floor(Date.now() / 1000) - 10 },
      ]) {
        const { send, calls } = setup({});

        const response = await send(
          "GET",
          "/installations/icfg_1",
          undefined,
          await oidc(extra),
        );

        expect(response.status).toBe(403);
        expect(calls).toEqual([]);
      }
    });

    it("answers 403 when the token names another installation than the path", async () => {
      const { send, calls } = setup({});
      const response = await send("GET", "/installations/icfg_2");
      const problem = (await response.json()) as Record<string, unknown>;

      expect(response.status).toBe(403);
      expect(problem["instance"]).toBe("/api/vercel/v1/installations/icfg_2");
      expect(calls).toEqual([]);
    });

    it("answers 404 for a route outside the Partner API", async () => {
      const { send } = setup({});

      expect((await send("GET", "/installations/icfg_1/nope")).status).toBe(
        404,
      );
      expect((await send("GET", "/other")).status).toBe(404);
    });
  });

  describe("installations", () => {
    it("stores the installation, seals the access token and links the tenant from install", async () => {
      const { send, calls } = setup(
        {
          upsert_marketplace_installation: installationRow(),
          link_marketplace_tenant: installationRow({ tenant: "org_9" }),
        },
        {
          install: ({ scopes }) =>
            Promise.resolve({
              tenant: "org_9",
              tenantCreated: scopes.length > 0,
            }),
        },
      );

      const response = await send("PUT", "/installations/icfg_1", {
        scopes: ["read-write:integration-resource"],
        acceptedPolicies: { toc: "2026-01-01T00:00:00Z" },
        credentials: { access_token: "vat_1", token_type: "Bearer" },
        account: { name: "Acme", url: "https://acme.test" },
      });

      expect(response.status).toBe(200);
      expect(calls).toEqual([
        [
          "upsert_marketplace_installation",
          expect.objectContaining({
            configuration_id: "icfg_1",
            team_id: "team_1",
            user_id: "user_1",
            metadata: {
              account: { name: "Acme", url: "https://acme.test" },
              scopes: ["read-write:integration-resource"],
              acceptedPolicies: { toc: "2026-01-01T00:00:00Z" },
            },
          }),
        ],
        [
          "seal_marketplace_access_token",
          { configuration_id: "icfg_1", access_token: "vat_1" },
        ],
        [
          "link_marketplace_tenant",
          { configuration_id: "icfg_1", tenant: "org_9", created: true },
        ],
      ]);
      expect(JSON.stringify(calls[0])).not.toContain("vat_1");
    });

    it("returns and changes the installation's plan", async () => {
      const { send, calls } = setup({
        marketplace_installation: installationRow({
          metadata: { billingPlanId: "pro" },
        }),
        upsert_marketplace_installation: installationRow(),
      });

      const read = await send("GET", "/installations/icfg_1");

      expect(await read.json()).toEqual({ billingPlan: { id: "pro" } });

      const patched = await send("PATCH", "/installations/icfg_1", {
        billingPlanId: "team",
      });

      expect(patched.status).toBe(200);
      expect(calls.at(-1)).toEqual([
        "upsert_marketplace_installation",
        expect.objectContaining({ metadata: { billingPlanId: "team" } }),
      ]);
    });

    it("answers 404 for an installation it does not know", async () => {
      const { send } = setup({});

      expect((await send("GET", "/installations/icfg_1")).status).toBe(404);
    });

    it("tears down every resource, removes the installation and deletes an empty created tenant", async () => {
      const order: string[] = [];
      const deleted: string[] = [];

      const { send, names } = setup(
        {
          marketplace_installation: installationRow({
            tenant: "org_install",
            tenant_created: true,
          }),
          marketplace_resources: [
            resourceRow({ tenant: "org_res", tenant_created: true }),
          ],
          delete_marketplace_resource: resourceRow({ status: "deleted" }),
          remove_marketplace_installation: installationRow({
            tenant: "org_install",
            tenant_created: true,
            status: "removed",
          }),
        },
        {
          resources: {
            provision: () => Promise.resolve({ secrets: [] }),
            deprovision: ({ resource }) => {
              order.push(`deprovision ${resource.externalId}`);

              return Promise.resolve();
            },
          },
          organizations: {
            members: (id) =>
              AsyncResult.ok(id === "org_res" ? [] : [{ id: "m1" }]),
            delete: (id) => {
              deleted.push(id);

              return AsyncResult.ok(true);
            },
          },
        },
      );

      const response = await send("DELETE", "/installations/icfg_1");

      expect(await response.json()).toEqual({ finalized: true });
      expect(order).toEqual(["deprovision res_1"]);
      expect(deleted).toEqual(["org_res"]);
      expect(names()).toEqual([
        "marketplace_installation",
        "marketplace_resources",
        "delete_marketplace_resource",
        "remove_marketplace_installation",
      ]);
    });

    it("leaves a tenant the installation did not create, and calls a custom removeTenant", async () => {
      const removals: unknown[] = [];

      const { send } = setup(
        {
          marketplace_installation: installationRow({ tenant: "org_1" }),
          marketplace_resources: [],
          remove_marketplace_installation: installationRow({
            tenant: "org_1",
            status: "removed",
          }),
        },
        {
          removeTenant: (input) => {
            removals.push({ tenant: input.tenant, created: input.created });

            return Promise.resolve();
          },
        },
      );

      await send("DELETE", "/installations/icfg_1");

      expect(removals).toEqual([{ tenant: "org_1", created: false }]);
    });
  });

  describe("resources", () => {
    it("provisions a resource with its tenant, and keeps only the secret refs", async () => {
      const seen: unknown[] = [];

      const { send, calls } = setup(
        {
          marketplace_installation: installationRow(),
          upsert_marketplace_resource: resourceRow({ plan_id: "free" }),
        },
        {
          resourceId: () => "res_new",
          plans: [
            {
              id: "free",
              name: "Free",
              type: "subscription",
              billing: { items: [] },
            },
          ],
          resources: {
            provision: (input) => {
              seen.push({
                id: input.resource.id,
                plan: input.plan?.id,
                environments: input.environments,
              });

              return Promise.resolve({
                tenant: "org_1",
                tenantCreated: true,
                secrets: [
                  {
                    name: "APP_API_KEY",
                    value: "sk_live",
                    ref: "key_1",
                    environmentOverrides: { preview: "sk_preview" },
                  },
                ],
              });
            },
          },
        },
      );

      const response = await send("POST", "/installations/icfg_1/resources", {
        productId: "prod_1",
        name: "db",
        metadata: { region: "fra1" },
        billingPlanId: "free",
      });

      const body = (await response.json()) as Record<string, unknown>;

      expect(response.status).toBe(201);
      expect(seen).toEqual([
        {
          id: "res_new",
          plan: "free",
          environments: ["production", "preview", "development"],
        },
      ]);
      expect(body).toMatchObject({
        id: "res_1",
        productId: "prod_1",
        metadata: { region: "fra1" },
        status: "ready",
        billingPlan: { id: "free" },
        secrets: [
          {
            name: "APP_API_KEY",
            value: "sk_live",
            environmentOverrides: { preview: "sk_preview" },
          },
        ],
      });
      expect(JSON.stringify(body)).not.toContain("key_1");
      expect(calls.at(-1)).toEqual([
        "set_marketplace_resource_state",
        {
          configuration_id: "icfg_1",
          external_id: "res_new",
          tenant: "org_1",
          tenant_created: true,
          secret_refs: ["key_1"],
        },
      ]);
      expect(JSON.stringify(calls)).not.toContain("sk_live");
    });

    it("answers 500 when the provision hook returns secrets of the wrong shape", async () => {
      for (const secrets of [
        "nope",
        [{ name: "1BAD", value: "x" }],
        [{ name: "OK", value: 1 }],
        [{ name: "OK", value: "x", environmentOverrides: { staging: "y" } }],
      ]) {
        const { send } = setup(
          { marketplace_installation: installationRow() },
          {
            resources: {
              provision: () =>
                // SAFETY: the test feeds a shape the type forbids on purpose.
                Promise.resolve({ secrets } as unknown as { secrets: [] }),
            },
          },
        );

        expect(
          (await send("PUT", "/installations/icfg_1/resources/res_1", {}))
            .status,
        ).toBe(500);
      }
    });

    it("reads, updates and deletes a resource", async () => {
      const updates: unknown[] = [];

      const { send, calls } = setup(
        {
          marketplace_installation: installationRow(),
          marketplace_resource: resourceRow(),
          upsert_marketplace_resource: resourceRow({ name: "renamed" }),
          delete_marketplace_resource: resourceRow({ status: "deleted" }),
        },
        {
          resources: {
            provision: () => Promise.resolve({ secrets: [] }),
            update: ({ changes }) => {
              updates.push(changes);

              return Promise.resolve();
            },
          },
        },
      );

      const read = await send("GET", "/installations/icfg_1/resources/res_1");

      expect(await read.json()).toEqual({
        id: "res_1",
        productId: "prod_1",
        name: "db",
        metadata: { region: "fra1" },
        status: "ready",
        billingPlan: { id: "free" },
      });

      const patched = await send(
        "PATCH",
        "/installations/icfg_1/resources/res_1",
        {
          name: "renamed",
        },
      );

      expect(await patched.json()).toMatchObject({ name: "renamed" });
      expect(updates).toEqual([{ name: "renamed" }]);

      const removed = await send(
        "DELETE",
        "/installations/icfg_1/resources/res_1",
      );

      expect(removed.status).toBe(204);
      expect(calls.at(-1)?.[0]).toBe("delete_marketplace_resource");
    });

    it("answers 404 for a deleted resource and 405 for a method it does not route", async () => {
      const { send } = setup({
        marketplace_installation: installationRow(),
        marketplace_resource: resourceRow({ status: "deleted" }),
      });

      expect(
        (await send("GET", "/installations/icfg_1/resources/res_1")).status,
      ).toBe(404);

      const wrong = await send("GET", "/installations/icfg_1/resources");

      expect(wrong.status).toBe(405);
      expect(wrong.headers.get("allow")).toBe("POST");
    });

    it("answers 400 for a body that is not a JSON object", async () => {
      const { send } = setup({ marketplace_installation: installationRow() });

      expect(
        (await send("POST", "/installations/icfg_1/resources", [1])).status,
      ).toBe(400);
    });
  });

  describe("secret rotation", () => {
    it("revokes the previous secrets only after the new ones are issued and stored", async () => {
      const order: string[] = [];

      const { send, calls } = setup(
        {
          marketplace_installation: installationRow(),
          marketplace_resource: resourceRow({ secret_refs: ["key_1"] }),
          set_marketplace_resource_state: () => {
            order.push("store");

            return null;
          },
        },
        {
          resources: {
            provision: () => Promise.resolve({ secrets: [] }),
            rotate: () => {
              order.push("rotate");

              return Promise.resolve({
                secrets: [{ name: "APP_API_KEY", value: "sk_2", ref: "key_2" }],
              });
            },
            revoke: ({ previous, delayHours }) => {
              order.push(`revoke ${previous.join(",")} after ${delayHours}h`);

              return Promise.resolve();
            },
          },
        },
      );

      const response = await send(
        "POST",
        "/installations/icfg_1/resources/res_1/secrets/rotate",
        { reason: "leak", delayOldSecretsExpirationHours: 2 },
      );

      expect(await response.json()).toEqual({
        sync: true,
        secrets: [{ name: "APP_API_KEY", value: "sk_2" }],
      });
      expect(order).toEqual(["rotate", "store", "revoke key_1 after 2h"]);
      expect(calls.at(-1)?.[1]).toMatchObject({ secret_refs: ["key_2"] });
    });

    it("keeps the previous secrets when the rotation fails", async () => {
      const revoked: unknown[] = [];

      const { send, names } = setup(
        {
          marketplace_installation: installationRow(),
          marketplace_resource: resourceRow({ secret_refs: ["key_1"] }),
        },
        {
          resources: {
            provision: () => Promise.resolve({ secrets: [] }),
            rotate: () => Promise.reject(new Error("key service down")),
            revoke: (input) => {
              revoked.push(input);

              return Promise.resolve();
            },
          },
        },
      );

      const response = await send(
        "POST",
        "/installations/icfg_1/resources/res_1/secrets/rotate",
      );

      expect(response.status).toBe(500);
      expect(revoked).toEqual([]);
      expect(names()).not.toContain("set_marketplace_resource_state");
    });

    it("answers that rotation is unsupported without a rotate hook", async () => {
      const { send } = setup({
        marketplace_installation: installationRow(),
        marketplace_resource: resourceRow(),
      });

      const response = await send(
        "POST",
        "/installations/icfg_1/resources/res_1/secrets/rotate",
      );

      expect(response.status).toBe(501);
    });
  });

  describe("plans", () => {
    it("lists a free plan with empty billing items for a product and an installation", async () => {
      const free = {
        id: "free",
        name: "Free",
        type: "subscription" as const,
        scope: "resource" as const,
        paymentMethodRequired: false,
        billing: { items: [] },
      };

      const { send } = setup(
        { marketplace_installation: installationRow() },
        {
          plans: ({ productId }) =>
            Promise.resolve(productId === "prod_other" ? [] : [free]),
        },
      );

      const product = await send("GET", "/products/prod_1/plans");

      expect(await product.json()).toEqual({ plans: [free] });

      const installation = await send("GET", "/installations/icfg_1/plans");

      expect(await installation.json()).toEqual({ plans: [free] });
      expect(
        (await send("POST", "/products/prod_1/plans")).headers.get("allow"),
      ).toBe("GET");
    });
  });

  describe("edge cases", () => {
    it("stores an installation without a body, token or install hook", async () => {
      const { send, names } = setup({
        upsert_marketplace_installation: installationRow(),
      });

      const response = await send(
        "PUT",
        "/installations/icfg_1",
        undefined,
        await oidc({ account_id: undefined, user_id: undefined }),
      );

      expect(response.status).toBe(200);
      expect(names()).toEqual(["upsert_marketplace_installation"]);
    });

    it("skips linking when install returns no tenant", async () => {
      const { send, names } = setup(
        { upsert_marketplace_installation: installationRow() },
        { install: () => Promise.resolve() },
      );

      await send("PUT", "/installations/icfg_1", { scopes: "all" });

      expect(names()).toEqual(["upsert_marketplace_installation"]);
    });

    it("returns an installation without a plan, and patches nothing without one", async () => {
      const { send, calls } = setup({
        marketplace_installation: installationRow(),
        upsert_marketplace_installation: installationRow(),
      });

      expect(await (await send("GET", "/installations/icfg_1")).json()).toEqual(
        {},
      );

      await send("PATCH", "/installations/icfg_1", {});

      expect(calls.at(-1)?.[1]).toMatchObject({ metadata: {} });
    });

    it("finalizes a removed installation without tenants, keeping the found row", async () => {
      const { send } = setup({
        marketplace_installation: installationRow(),
        marketplace_resources: [resourceRow()],
        delete_marketplace_resource: null,
        remove_marketplace_installation: null,
      });

      const response = await send("DELETE", "/installations/icfg_1");

      expect(await response.json()).toEqual({ finalized: true });
    });

    it("keeps a created resource tenant without organizations, and one that has members", async () => {
      const deleted: string[] = [];

      const row = {
        marketplace_installation: installationRow(),
        marketplace_resource: resourceRow({
          tenant: "org_1",
          tenant_created: true,
        }),
        delete_marketplace_resource: resourceRow({ status: "deleted" }),
      };

      const bare = setup(row);

      expect(
        (await bare.send("DELETE", "/installations/icfg_1/resources/res_1"))
          .status,
      ).toBe(204);

      const busy = setup(row, {
        organizations: {
          members: () => AsyncResult.ok([{ id: "m1" }]),
          delete: (id) => {
            deleted.push(id);

            return AsyncResult.ok(true);
          },
        },
      });

      await busy.send("DELETE", "/installations/icfg_1/resources/res_1");

      expect(deleted).toEqual([]);
    });

    it("answers 405 for methods the installation, resource, rotate and plans routes don't take", async () => {
      const { send } = setup({
        marketplace_installation: installationRow(),
        marketplace_resource: resourceRow(),
      });

      for (const [method, path, allow] of [
        ["POST", "/installations/icfg_1", "PUT, GET, PATCH, DELETE"],
        [
          "POST",
          "/installations/icfg_1/resources/res_1",
          "PUT, GET, PATCH, DELETE",
        ],
        ["GET", "/installations/icfg_1/resources/res_1/secrets/rotate", "POST"],
        ["DELETE", "/installations/icfg_1/plans", "GET"],
      ] as const) {
        const response = await send(method, path);

        expect(response.status).toBe(405);
        expect(response.headers.get("allow")).toBe(allow);
      }
    });

    it("answers 404 for unknown paths below an installation and a resource", async () => {
      const { send } = setup({ marketplace_installation: installationRow() });

      for (const path of [
        "/installations/icfg_1/resources/res_1/secrets",
        "/installations/icfg_1/resources/res_1/other/rotate",
        "/products/prod_1",
        "/",
      ]) {
        expect((await send("GET", path)).status).toBe(404);
      }

      const outside = setup({});
      const response = await outside.send("GET", "/../health");

      expect(response.status).toBe(404);
    });

    it("answers 400 for a body that is not JSON", async () => {
      const { send } = setup({
        marketplace_installation: installationRow(),
        upsert_marketplace_installation: installationRow(),
      });

      const response = await send("PATCH", "/installations/icfg_1", undefined);

      expect(response.status).toBe(200);

      const handler = await send("PUT", "/installations/icfg_1", "x");

      expect(handler.status).toBe(400);
    });

    it("provisions without a tenant, name, plan or plans, and with a prefixed secret", async () => {
      const { send, calls } = setup(
        {
          marketplace_installation: installationRow(),
          upsert_marketplace_resource: resourceRow({
            plan_id: null,
            metadata: {},
          }),
        },
        {
          resources: {
            provision: ({ plan }) =>
              Promise.resolve({
                secrets: [
                  {
                    name: "APP_URL",
                    value: plan === undefined ? "https://app.test" : "x",
                    prefix: "NEXT_PUBLIC_",
                  },
                ],
              }),
          },
        },
      );

      const response = await send(
        "PUT",
        "/installations/icfg_1/resources/res_1",
      );

      const body = (await response.json()) as Record<string, unknown>;

      expect(body).toEqual({
        id: "res_1",
        productId: undefined,
        name: "db",
        metadata: {},
        status: "ready",
        secrets: [
          {
            name: "APP_URL",
            value: "https://app.test",
            prefix: "NEXT_PUBLIC_",
          },
        ],
      });
      expect(calls.at(-2)?.[1]).toMatchObject({ name: "res_1" });
      expect(calls.at(-1)?.[1]).toMatchObject({
        tenant: null,
        tenant_created: null,
        secret_refs: [],
      });
    });

    it("refuses secrets with a bad prefix, ref, overrides or entry", async () => {
      for (const secrets of [
        ["nope"],
        [{ name: "A", value: "x", prefix: 1 }],
        [{ name: "A", value: "x", ref: 1 }],
        [{ name: "A", value: "x", environmentOverrides: "y" }],
        [{ name: "A", value: "x", environmentOverrides: { preview: 1 } }],
      ]) {
        const { send } = setup(
          { marketplace_installation: installationRow() },
          {
            resources: {
              provision: () =>
                // SAFETY: the test feeds a shape the type forbids on purpose.
                Promise.resolve({ secrets } as unknown as { secrets: [] }),
            },
          },
        );

        expect(
          (await send("PUT", "/installations/icfg_1/resources/res_1")).status,
        ).toBe(500);
      }
    });

    it("patches a resource's metadata and plan without an update hook", async () => {
      const { send, calls } = setup({
        marketplace_installation: installationRow(),
        marketplace_resource: resourceRow(),
        upsert_marketplace_resource: resourceRow({ plan_id: "pro" }),
      });

      const response = await send(
        "PATCH",
        "/installations/icfg_1/resources/res_1",
        { metadata: { region: "iad1" }, billingPlanId: "pro" },
      );

      expect(response.status).toBe(200);
      expect(calls.at(-1)?.[1]).toMatchObject({
        name: "db",
        plan_id: "pro",
        metadata: { vercel: { region: "iad1" } },
      });
    });

    it("rotates without a revoke hook, and without previous refs to revoke", async () => {
      const revoked: unknown[] = [];

      for (const [refs, revoke] of [
        [["key_1"], undefined],
        [
          [],
          (input: unknown) => {
            revoked.push(input);

            return Promise.resolve();
          },
        ],
      ] as const) {
        const { send } = setup(
          {
            marketplace_installation: installationRow(),
            marketplace_resource: resourceRow({ secret_refs: refs }),
          },
          {
            resources: {
              provision: () => Promise.resolve({ secrets: [] }),
              rotate: () =>
                Promise.resolve({ secrets: [{ name: "A", value: "x" }] }),
              ...(revoke === undefined ? {} : { revoke }),
            },
          },
        );

        const response = await send(
          "POST",
          "/installations/icfg_1/resources/res_1/secrets/rotate",
          { delayOldSecretsExpirationHours: "2" },
        );

        expect(response.status).toBe(200);
      }

      expect(revoked).toEqual([]);
    });

    it("exposes internal messages only when asked, and renders the problem format it is given", async () => {
      const failing = {
        marketplace_installation: () => {
          throw new Error("db exploded");
        },
      };

      const hidden = await setup(failing).send("GET", "/installations/icfg_1");

      const shown = await setup(failing, { expose: true }).send(
        "GET",
        "/installations/icfg_1",
      );

      expect(JSON.stringify(await hidden.json())).not.toContain("db exploded");
      expect(JSON.stringify(await shown.json())).toContain("db exploded");
    });

    it("gives a POSTed resource a random id by default", async () => {
      const ids: string[] = [];

      const { send } = setup(
        {
          marketplace_installation: installationRow(),
          upsert_marketplace_resource: resourceRow(),
        },
        {
          resources: {
            provision: ({ resource }) => {
              ids.push(resource.id);

              return Promise.resolve({ secrets: [] });
            },
          },
        },
      );

      await send("POST", "/installations/icfg_1/resources", {});

      expect(ids[0]).toMatch(/^[0-9a-f-]{36}$/u);
    });
  });
});
