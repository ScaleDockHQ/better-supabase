import { describe, expect, test, vi } from "vitest";

import {
  isProjectRef,
  managementClient,
  ManagementError,
} from "../../lib/supabase-management";

type JsonBody = Record<string, string | number | boolean>;

function respond(body: string, status = 200) {
  return vi.fn<typeof fetch>(() =>
    Promise.resolve(new Response(body, { status })),
  );
}

function respondJson(body: JsonBody | readonly JsonBody[], status = 200) {
  return respond(JSON.stringify(body), status);
}

const project = {
  id: "abcdefghijklmnopqrst",
  ref: "abcdefghijklmnopqrst",
  name: "my-app",
  organization_slug: "acme",
  region: "us-east-1",
  status: "ACTIVE_HEALTHY",
};

test("isProjectRef accepts lowercase refs only", () => {
  expect(isProjectRef("abcdefghijklmnopqrst")).toBe(true);
  expect(isProjectRef("../v1/organizations")).toBe(false);
  expect(isProjectRef("")).toBe(false);
});

describe("managementClient", () => {
  test("sends the bearer token and parses projects", async () => {
    const fetchImpl = respondJson([project]);

    await expect(
      managementClient("token", fetchImpl).projects(),
    ).resolves.toMatchObject([{ ref: project.ref, status: "ACTIVE_HEALTHY" }]);

    const [url, init] = fetchImpl.mock.calls[0] ?? [];

    expect(String(url)).toBe("https://api.supabase.com/v1/projects");
    expect(new Headers(init?.headers).get("Authorization")).toBe(
      "Bearer token",
    );
  });

  test("creates a project in a smart region group", async () => {
    const fetchImpl = respondJson(project, 201);

    await managementClient("token", fetchImpl).createProject({
      name: "my-app",
      organizationSlug: "acme",
      region: "emea",
      dbPass: "password",
    });

    const [, init] = fetchImpl.mock.calls[0] ?? [];

    expect(init?.method).toBe("POST");
    expect(JSON.parse(String(init?.body))).toEqual({
      name: "my-app",
      organization_slug: "acme",
      db_pass: "password",
      region_selection: { type: "smartGroup", code: "emea" },
    });
  });

  test("counts public tables and reads database health", async () => {
    await expect(
      managementClient("token", respondJson([{ count: "3" }])).publicTableCount(
        project.ref,
      ),
    ).resolves.toBe(3);

    await expect(
      managementClient(
        "token",
        respondJson([{ name: "db", healthy: true, status: "ACTIVE_HEALTHY" }]),
      ).databaseHealthy(project.ref),
    ).resolves.toBe(true);
  });

  test("posts the migration by name", async () => {
    const fetchImpl = respond("");

    await managementClient("token", fetchImpl).applyMigration(
      project.ref,
      "better_supabase_blocks",
      "select 1;",
    );

    const [url, init] = fetchImpl.mock.calls[0] ?? [];

    expect(String(url)).toBe(
      `https://api.supabase.com/v1/projects/${project.ref}/database/migrations`,
    );
    expect(JSON.parse(String(init?.body))).toEqual({
      name: "better_supabase_blocks",
      query: "select 1;",
    });
  });

  test("turns an error body into a ManagementError with the status", async () => {
    const migration = managementClient(
      "token",
      respondJson({ message: "relation already exists" }, 400),
    ).applyMigration(project.ref, "m", "q");

    await expect(migration).rejects.toBeInstanceOf(ManagementError);
    await expect(migration).rejects.toMatchObject({
      message: "relation already exists",
      status: 400,
    });
  });

  test("handles non-JSON errors and unexpected shapes", async () => {
    await expect(
      managementClient(
        "token",
        respond("<html>Bad gateway</html>", 502),
      ).organizations(),
    ).rejects.toMatchObject({ status: 502 });

    await expect(
      managementClient(
        "token",
        respondJson({ unexpected: true }),
      ).organizations(),
    ).rejects.toBeInstanceOf(ManagementError);
  });
});
