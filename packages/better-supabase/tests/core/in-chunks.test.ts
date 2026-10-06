import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const ids = Array.from(
  { length: 300 },
  (_, index) => `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
);

function listOf(param: string | null): string[] {
  return (param ?? "").replaceAll(/^in\.\(|\)$/g, "").split(",");
}

describe("oversized in lists", () => {
  const betterSupabase = defineSupabase(schema, { maxUrlLength: 4000 });

  it("splits an unpaginated read and merges the rows", async () => {
    const { client, requests } = capturingClient((request) => ({
      body: listOf(request.params.get("id")).map((id) => ({ id })),
    }));
    const rows = await betterSupabase
      .connect(client)
      .customers.findMany({
        select: ["id"],
        where: { id: { in: ids }, status: "active" },
        orderBy: { id: "desc" },
      })
      .orThrow();
    expect(requests.length).toBeGreaterThan(1);
    for (const request of requests) {
      expect(request.params.get("status")).toBe("eq.active");
      expect(request.params.toString().length).toBeLessThanOrEqual(4000);
    }
    expect(
      requests.flatMap((request) => listOf(request.params.get("id"))),
    ).toEqual(ids);
    expect(rows.map((row) => row.id)).toEqual([...ids].reverse());
  });

  it("keeps a read that fits in one request", async () => {
    const { client, requests } = capturingClient();
    await betterSupabase
      .connect(client)
      .customers.findMany({ where: { id: { in: ids.slice(0, 10) } } })
      .orThrow();
    expect(requests).toHaveLength(1);
  });

  it("sorts merged rows with nulls where Postgres puts them", async () => {
    const { client } = capturingClient((request) => ({
      body: listOf(request.params.get("id")).map((id, index) => ({
        id,
        createdAt:
          index % 50 === 0
            ? null
            : `2026-01-01T00:00:${String(index % 60).padStart(2, "0")}+00:00`,
      })),
    }));
    const rows = await betterSupabase
      .connect(client)
      .customers.findMany({
        select: ["id", "createdAt"],
        where: { id: { in: ids } },
        orderBy: [{ createdAt: "asc" }, { id: "asc" }],
      })
      .orThrow();
    const times: unknown[] = rows.map((row) => row.createdAt);
    const firstNull = times.indexOf(null);
    expect(times.slice(firstNull).every((time) => time === null)).toBe(true);
    const present = times.slice(0, firstNull);
    expect(present).toEqual(
      [...present].sort((a, b) => String(a).localeCompare(String(b))),
    );
  });

  it.each([
    [
      "a paginated read",
      { where: { id: { in: ids } }, limit: 10 },
      "limit, offset, count or single row",
    ],
    [
      "an order on text",
      {
        where: { id: { in: ids } },
        orderBy: { name: "asc" },
        select: ["id", "name"],
      },
      'order on "name"',
    ],
    [
      "an order on an unselected column",
      {
        where: { id: { in: ids } },
        orderBy: { createdAt: "asc" },
        select: ["id"],
      },
      'order on "created_at"',
    ],
    [
      "a long list inside OR",
      { where: { OR: [{ id: { in: ids } }, { kvk: "1" }] } },
      "no top-level in list",
    ],
  ] as const)(
    "returns invalid_request for %s",
    async (_name, args, message) => {
      const { client, requests } = capturingClient();
      const result = await betterSupabase
        .connect(client)
        .customers.findMany(args as never);
      expect(result.error).toMatchObject({
        kind: "invalid_request",
        table: "customers",
        message: expect.stringContaining(message),
      });
      expect(requests).toHaveLength(0);
    },
  );

  it("returns invalid_request for a page of a long list", async () => {
    const { client, requests } = capturingClient();
    const page = await betterSupabase.connect(client).customers.paginate({
      where: { id: { in: ids } },
      include: { notes: { where: { OR: [{ kind: "call" }, { body: "x" }] } } },
      size: 20,
    });
    expect(page.error?.kind).toBe("invalid_request");
    expect(requests).toHaveLength(0);
  });

  it("refuses a read whose other filters leave no room for the list", async () => {
    const { client } = capturingClient();
    const result = await defineSupabase(schema, { maxUrlLength: 200 })
      .connect(client)
      .customers.findMany({
        where: { id: { in: ids.slice(0, 20) }, name: { in: ids.slice(0, 5) } },
      });
    expect(result.error?.message).toContain("leaves no room");
  });

  it("passes the first error through", async () => {
    let call = 0;
    const { client } = capturingClient(() => {
      call += 1;
      return call === 2
        ? { status: 500, body: { code: "XX000", message: "boom" } }
        : { body: [] };
    });
    const result = await betterSupabase
      .connect(client)
      .customers.findMany({ where: { id: { in: ids } } });
    expect(result.error?.message).toBe("boom");
  });
});
