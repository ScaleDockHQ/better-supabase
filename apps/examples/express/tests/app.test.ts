import type { AddressInfo } from "node:net";

import { signLocalJwt } from "better-supabase/testing";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { app } from "../src/app.ts";

const ACME = "00000000-0000-4000-8000-000000000001";
const USER = "00000000-0000-4000-8000-0000000000ff";

async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${process.env["SUPABASE_URL"]}/rest/v1/`, {
      headers: { apikey: process.env["SUPABASE_PUBLISHABLE_KEY"] ?? "" },
      signal: AbortSignal.timeout(1000),
    });
    return response.status < 500;
  } catch {
    return false;
  }
}

const live = await reachable();

describe.skipIf(!live)("Express example against the local stack", () => {
  const server = app.listen(0);
  let base = "";
  beforeAll(() => {
    const { port } = server.address() as AddressInfo;
    base = `http://127.0.0.1:${String(port)}/api`;
  });
  afterAll(() => {
    server.close();
  });

  const asMember = async (path: string, init: RequestInit = {}) =>
    fetch(`${base}${path}`, {
      ...init,
      headers: {
        authorization: `Bearer ${await signLocalJwt({ sub: USER, tenant_id: ACME, user_role: "member" })}`,
      },
    });

  it("lists the tenant's customers as the caller", async () => {
    const response = await asMember("/customers");
    expect(response.status).toBe(200);
    const rows = (await response.json()) as { organizationId: string }[];
    expect(rows.every((row) => row.organizationId === ACME)).toBe(true);
  });

  it("answers a missing row with Problem Details", async () => {
    const response = await asMember(`/customers/${USER}`);
    expect(response.status).toBe(404);
    expect(response.headers.get("content-type")).toContain(
      "application/problem+json",
    );
  });

  it("refuses a member on the admin route", async () => {
    const response = await asMember(`/customers/${USER}/archive`, {
      method: "POST",
    });
    expect(response.status).toBe(403);
  });

  it("refuses anonymous callers", async () => {
    expect((await fetch(`${base}/customers`)).status).toBe(401);
  });
});
