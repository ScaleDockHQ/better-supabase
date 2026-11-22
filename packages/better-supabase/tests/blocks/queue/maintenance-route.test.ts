import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { maintenanceRoute } from "../../../src/blocks/queue/maintenance-route.ts";

function transport(held = false): {
  readonly transport: BlockTransport;
  readonly calls: string[];
} {
  const calls: string[] = [];

  return {
    calls,
    transport: {
      call: (_schema, fn) => {
        calls.push(fn);

        switch (fn) {
          case "acquire_lease": {
            return Promise.resolve(held ? null : "holder");
          }

          case "maintenance_scheduler": {
            return Promise.resolve("none");
          }

          case "maintenance": {
            return Promise.resolve([{ job: "purge" }]);
          }

          default: {
            return Promise.resolve(null);
          }
        }
      },
    },
  };
}

const request = (headers: Record<string, string> = {}): Request =>
  new Request("https://app.test/api/maintenance", {
    headers: { authorization: "Bearer s", ...headers },
  });

describe("maintenanceRoute", () => {
  it("runs maintenance under the lease and releases it", async () => {
    const t = transport();
    const route = maintenanceRoute({ secret: "s", transport: t.transport });
    const response = await route(request());
    expect(await response.json()).toEqual({
      scheduler: "none",
      jobs: [{ job: "purge" }],
    });
    expect(t.calls).toEqual([
      "acquire_lease",
      "maintenance_scheduler",
      "maintenance",
      "release_lease",
    ]);
  });

  it("skips while another run holds the lease", async () => {
    const t = transport(true);
    const route = maintenanceRoute({ secret: "s", transport: t.transport });
    expect(await (await route(request())).json()).toEqual({
      skipped: "overlap",
    });
    expect(t.calls).toEqual(["acquire_lease"]);
  });

  it("skips a late run", async () => {
    const t = transport();

    const route = maintenanceRoute({
      secret: "s",
      transport: t.transport,
      maxLateSeconds: 1,
    });

    const response = await route(
      request({ "ce-time": "2020-01-01T00:00:00Z" }),
    );

    expect(await response.json()).toEqual({ skipped: "late" });
    expect(t.calls).toEqual([]);
  });

  it("answers 500 with the error when maintenance fails", async () => {
    const onError = vi.fn();

    const route = maintenanceRoute({
      secret: "s",
      leaseSeconds: false,
      onError,
      transport: { call: () => Promise.reject(new Error("down")) },
    });

    const response = await route(request());
    expect(response.status).toBe(500);
    expect(onError).toHaveBeenCalledOnce();
  });

  it("passes the schema and force on, and reports a lease that can't be taken", async () => {
    const onError = vi.fn();
    const schemas: string[] = [];
    const calls: string[] = [];

    const route = maintenanceRoute({
      secret: "s",
      schema: "ops",
      force: true,
      leaseSeconds: 60,
      onError,
      transport: {
        call: (schema, fn) => {
          schemas.push(schema);
          calls.push(fn);

          return fn === "acquire_lease"
            ? Promise.reject(new Error("down"))
            : Promise.resolve(null);
        },
      },
    });

    const response = await route(request());

    expect(await response.json()).toEqual({ skipped: "overlap" });
    expect(calls).toEqual(["acquire_lease"]);
    expect(schemas).toEqual(["ops"]);
    expect(onError).toHaveBeenCalledOnce();
  });
});
