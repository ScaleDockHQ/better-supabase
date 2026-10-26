import type { APIRequestContext } from "@playwright/test";

import { expect, test } from "@playwright/test";
import * as v from "valibot";

import { accessToken } from "./tokens";

/**
 * `/api/v1` (`bsb.resources`) and `/api/mcp` (`createMcp`) as an API client
 * sees them: a Bearer token, RLS, and the permissions block deciding the
 * writes. No browser session is involved.
 */

const ACME = "00000000-0000-4000-8000-000000000001";
const GLOBEX = "00000000-0000-4000-8000-000000000002";

const Page = v.object({
  items: v.array(v.record(v.string(), v.unknown())),
  hasMore: v.boolean(),
});

const Problem = v.object({ status: v.number(), kind: v.string() });

const Teams = v.array(
  v.object({ name: v.string(), memberIds: v.array(v.string()) }),
);

const Roles = v.array(
  v.object({ key: v.string(), permissions: v.array(v.string()) }),
);

const Tools = v.object({
  result: v.object({ tools: v.array(v.object({ name: v.string() })) }),
});

const Call = v.object({
  result: v.object({
    isError: v.optional(v.boolean()),
    content: v.array(v.object({ text: v.string() })),
    structuredContent: v.optional(v.unknown()),
  }),
});

const bearer = (token: string) => ({ authorization: `Bearer ${token}` });

async function rpc(
  request: APIRequestContext,
  token: string,
  method: string,
  params?: { readonly name: string; readonly arguments: object },
) {
  const response = await request.post("/api/mcp", {
    headers: {
      ...bearer(token),
      accept: "application/json, text/event-stream",
    },
    data: { jsonrpc: "2.0", id: 1, method, params },
  });

  expect(response.status()).toBe(200);

  return response.json();
}

test.describe("REST API", () => {
  test("serves the app's tables and the blocks as the caller", async ({
    request,
  }) => {
    const headers = bearer(await accessToken("admin"));

    const organizations = v.parse(
      Page,
      await (await request.get("/api/v1/organizations", { headers })).json(),
    );

    expect(organizations.items.map((row) => row["name"])).toEqual(
      expect.arrayContaining(["Acme", "Globex"]),
    );

    const teams = await request.get(`/api/v1/organizations/${ACME}/teams`, {
      headers,
    });

    expect(teams.status()).toBe(200);
    expect(
      v.parse(Teams, await teams.json()).map((team) => team.name),
    ).toContain("Sales");

    const roles = v.parse(
      Roles,
      await (
        await request.get(`/api/v1/organizations/${ACME}/roles`, { headers })
      ).json(),
    );

    expect(roles.find((role) => role.key === "owner")?.permissions).toContain(
      "roles.manage",
    );

    // Roles act in the active organization; Globex isn't it.
    const other = await request.get(`/api/v1/organizations/${GLOBEX}/roles`, {
      headers,
    });

    expect(other.status()).toBe(404);
  });

  test("creates, reads and deletes a project", async ({ request }) => {
    const headers = bearer(await accessToken("admin"));

    const created = await request.post("/api/v1/projects", {
      headers,
      data: {
        name: "API project",
        organizationId: ACME,
        currency: "EUR",
        budgetMinor: "250000",
      },
    });

    expect(created.status()).toBe(201);
    const { id } = v.parse(v.object({ id: v.string() }), await created.json());

    try {
      const read = await request.get(`/api/v1/projects/${id}`, { headers });
      expect(await read.json()).toMatchObject({
        name: "API project",
        budgetMinor: "250000",
      });
    } finally {
      const deleted = await request.delete(`/api/v1/projects/${id}`, {
        headers,
      });

      expect(deleted.ok()).toBe(true);
    }
  });

  test("refuses a role override without roles.manage", async ({ request }) => {
    const response = await request.post(
      `/api/v1/organizations/${ACME}/role-overrides`,
      {
        headers: bearer(await accessToken("member")),
        data: {
          roleId: "member",
          permission: "customers.write",
          granted: false,
        },
      },
    );

    expect(response.status()).toBe(403);
    expect(v.parse(Problem, await response.json()).kind).toBe("forbidden");
  });

  test("answers 401 without a token", async ({ request }) => {
    expect((await request.get("/api/v1/customers")).status()).toBe(401);
  });

  test("publishes the OpenAPI document of the same map", async ({
    request,
  }) => {
    const document = v.parse(
      v.object({
        openapi: v.string(),
        paths: v.record(v.string(), v.unknown()),
      }),
      await (await request.get("/api/v1/openapi.json")).json(),
    );

    expect(document.openapi).toMatch(/^3\.1/);
    expect(Object.keys(document.paths)).toEqual(
      expect.arrayContaining([
        "/api/v1/customers/{id}/archive",
        "/api/v1/projects",
        "/api/v1/organizations/{id}/teams",
        "/api/v1/organizations/{id}/role-overrides",
      ]),
    );
  });
});

test.describe("MCP server", () => {
  test("challenges anonymous clients with RFC 9728 metadata", async ({
    request,
  }) => {
    const response = await request.post("/api/mcp", {
      headers: { accept: "application/json, text/event-stream" },
      data: { jsonrpc: "2.0", id: 1, method: "tools/list" },
    });

    expect(response.status()).toBe(401);
    expect(response.headers()["www-authenticate"]).toContain(
      "/.well-known/oauth-protected-resource/api/mcp",
    );

    const metadata = await request.get(
      "/.well-known/oauth-protected-resource/api/mcp",
    );

    expect(metadata.status()).toBe(200);
    expect(await metadata.json()).toMatchObject({
      resource: expect.stringMatching(/\/api\/mcp$/),
    });
  });

  test("lists table tools next to the app's own tools", async ({ request }) => {
    const tools = v.parse(
      Tools,
      await rpc(request, await accessToken("admin"), "tools/list"),
    );

    expect(tools.result.tools.map((tool) => tool.name)).toEqual(
      expect.arrayContaining([
        "customers_list",
        "tasks_update",
        "list_teams",
        "archive_customer",
        "set_permission_override",
      ]),
    );
  });

  test("runs tools as the caller", async ({ request }) => {
    const teams = v.parse(
      Call,
      await rpc(request, await accessToken("admin"), "tools/call", {
        name: "list_teams",
        arguments: { organizationId: ACME },
      }),
    );

    expect(teams.result.isError).not.toBe(true);
    // An array result has no `structuredContent`, only the JSON text.
    const [text] = teams.result.content;
    expect(
      v.parse(Teams, JSON.parse(text?.text ?? "[]")).length,
    ).toBeGreaterThan(0);

    const refused = v.parse(
      Call,
      await rpc(request, await accessToken("member"), "tools/call", {
        name: "set_permission_override",
        arguments: {
          role: "member",
          permission: "customers.write",
          granted: false,
        },
      }),
    );

    expect(refused.result.isError).toBe(true);
    expect(v.parse(Problem, refused.result.structuredContent).kind).toBe(
      "forbidden",
    );
  });
});
