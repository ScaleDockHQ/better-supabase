import { describe, expect, it } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { asSignedInUser } from "../../src/testing/as-user.ts";
import { schema } from "../fixtures/generated-camel.ts";

const segment = (value: unknown): string =>
  Buffer.from(JSON.stringify(value)).toString("base64url");

const TOKEN = `${segment({ alg: "none" })}.${segment({ sub: "u1", role: "authenticated", tenant_id: "t1", email: "a@x.test" })}.sig`;

describe("asSignedInUser", () => {
  const bsb = createSupabase(schema);

  it("signs in through Auth and takes the claims from the token", async () => {
    const seen: { url: string; body: string }[] = [];

    const user = await asSignedInUser(
      bsb,
      { email: "a@x.test", password: "pw" },
      {
        url: "http://stack.test",
        publishableKey: "pk",
        fetch: async (input: Request | string | URL, init?: RequestInit) => {
          seen.push({ url: String(input), body: String(init?.body) });

          return Response.json({ access_token: TOKEN });
        },
      },
    );

    expect(seen[0]?.url).toBe(
      "http://stack.test/auth/v1/token?grant_type=password",
    );
    expect(JSON.parse(seen[0]?.body ?? "{}")).toEqual({
      email: "a@x.test",
      password: "pw",
    });
    expect(user.token).toBe(TOKEN);
    expect(user.claims).toMatchObject({ sub: "u1", tenant_id: "t1" });
    expect(user.context.actor).toMatchObject({ id: "u1", email: "a@x.test" });
  });

  it("names the user when Auth refuses", async () => {
    await expect(
      asSignedInUser(
        bsb,
        { email: "no@x.test", password: "pw" },
        {
          url: "http://stack.test",
          publishableKey: "pk",
          fetch: async () => Response.json({ msg: "bad" }, { status: 400 }),
        },
      ),
    ).rejects.toThrow(/no@x.test/);
  });
});
