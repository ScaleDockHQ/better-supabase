import { describe, expect, it } from "vitest";

import { cronRoute } from "../../src/core/cron-route.ts";

const route = cronRoute(
  { name: "drain", secret: "s3cret" },
  (_request, instance) => Promise.resolve(Response.json({ instance })),
);

const call = (method: string, authorization?: string): Promise<Response> =>
  route(
    new Request("https://app.test/api/cron", {
      method,
      ...(authorization ? { headers: { authorization } } : {}),
    }),
  );

describe("cronRoute", () => {
  it("needs a secret", () => {
    expect(() =>
      cronRoute({ name: "relay", secret: undefined }, () =>
        Promise.resolve(new Response()),
      ),
    ).toThrow("relayRoute needs a secret, such as process.env.CRON_SECRET");
  });

  it("answers other methods with 405", async () => {
    const response = await call("DELETE", "Bearer s3cret");
    expect(response.status).toBe(405);
    expect(response.headers.get("allow")).toBe("GET, POST");
  });

  it("answers 401 without the bearer secret", async () => {
    const response = await call("GET", "Bearer nope");
    expect(response.status).toBe(401);
    expect(await response.text()).toContain("The drain route");
  });

  it("calls the handler with the request path for GET and POST", async () => {
    for (const method of ["GET", "POST"]) {
      const response = await call(method, "Bearer s3cret");
      expect(await response.json()).toEqual({ instance: "/api/cron" });
    }
  });

  describe('caller: "vercel-schedule"', () => {
    const scheduled = { "ce-type": "com.vercel.schedule.v1beta" };

    it("accepts a Vercel schedule run without the secret", async () => {
      const open = cronRoute(
        { name: "drain", secret: undefined, caller: "vercel-schedule" },
        () => Promise.resolve(new Response("ran")),
      );

      const response = await open(
        new Request("https://app.test/api/cron", {
          method: "POST",
          headers: scheduled,
        }),
      );

      expect(await response.text()).toBe("ran");
      expect(
        (await open(new Request("https://app.test/api/cron"))).status,
      ).toBe(401);
    });

    it("keeps the secret for other callers when one is set", async () => {
      const both = cronRoute(
        { name: "drain", secret: "s3cret", caller: "vercel-schedule" },
        () => Promise.resolve(new Response("ran")),
      );

      for (const headers of [scheduled, { authorization: "Bearer s3cret" }]) {
        const response = await both(
          new Request("https://app.test/api/cron", { method: "POST", headers }),
        );

        expect(response.status).toBe(200);
      }

      expect(
        (
          await both(
            new Request("https://app.test/api/cron", {
              method: "POST",
              headers: { "ce-type": "com.vercel.queue.v2beta" },
            }),
          )
        ).status,
      ).toBe(401);
    });
  });
});
