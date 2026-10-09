import { describe, expect, it } from "vitest";

import { DbException, dbError } from "../../src/core/errors.ts";
import { guard, problemOnError, toH3 } from "../../src/h3/index.ts";
import { withBetterSupabase } from "../../src/server/composite.ts";
import { requestAs, server } from "../fixtures/test-server.ts";

describe("h3 guard and problemOnError", () => {
  const middleware = toH3([
    withBetterSupabase(server, { allow: ["user", "anon"] }),
  ]);
  const admin = guard({ allow: ["user"] });

  const serve = (request: Request) => {
    const event = { req: request, context: {} };
    return middleware(event, () => admin(event, () => "secret"));
  };

  it("lets users through and refuses anonymous callers", async () => {
    const allowed = await serve(await requestAs({ role: "admin" }));
    expect(await allowed.text()).toBe("secret");
    const refused = await serve(await requestAs());
    expect(refused.status).toBe(401);
  });

  it("maps thrown DbExceptions and leaves other errors to H3", async () => {
    const onError = problemOnError();
    const event = { req: await requestAs(), context: {} };
    expect(
      onError(new DbException(dbError("conflict", "Taken")), event)?.status,
    ).toBe(409);
    expect(onError(new Error("boom"), event)).toBeUndefined();
  });
});
