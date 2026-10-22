import { Result, TaggedError } from "better-result";
import { describe, expect, it } from "vitest";

import type { DbError } from "../../src/core/errors.ts";

import { withBetterResult } from "../../src/better-result/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import {
  AsyncResult,
  defineBetterResultErrors,
} from "../../src/core/result.ts";
import { defineListQuery } from "../../src/list/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

class NotFound extends TaggedError("NotFound")<{
  message: string;
  error: DbError;
}> {}

class DbFailure extends TaggedError("DbFailure")<{
  message: string;
  error: DbError;
}> {}

const toResult = defineBetterResultErrors(
  Result,
  { not_found: NotFound },
  DbFailure,
);

const betterSupabase = defineSupabase(schema);
const customer = { id: "c1", name: "Acme" };

describe("withBetterResult", () => {
  it("returns better-result values from repository reads and writes", async () => {
    const { client, requests } = capturingClient((request) =>
      request.method === "GET"
        ? { body: [customer] }
        : { status: 201, body: [customer] },
    );

    const db = withBetterResult(betterSupabase.connect(client), toResult);

    const found = await db.customers.list({ select: ["id", "name"] });
    expect(found.isOk() && found.value).toEqual([customer]);

    const created = await db.customers.create({
      name: "Acme",
      organizationId: "o1",
    });

    expect(created.isOk()).toBe(true);
    expect(requests.map((request) => request.method)).toEqual(["GET", "POST"]);
  });

  it("maps errors through the converter", async () => {
    const { client } = capturingClient(() => ({ body: [] }));
    const db = withBetterResult(betterSupabase.connect(client), toResult);

    const missing = await db.customers.get("c1");
    expect(missing.isErr() && missing.error).toBeInstanceOf(NotFound);

    const { client: failing } = capturingClient(() => ({
      status: 409,
      body: { code: "23505", message: "duplicate key value" },
    }));

    const conflict = await withBetterResult(
      betterSupabase.connect(failing),
      toResult,
    ).customers.create({ name: "Acme", organizationId: "o1" });

    expect(conflict.isErr() && conflict.error).toBeInstanceOf(DbFailure);
  });

  it("accepts a Result namespace with mapError", async () => {
    const { client } = capturingClient(() => ({ body: [] }));

    const db = withBetterResult(betterSupabase.connect(client), {
      Result,
      mapError: (error: DbError) => error.kind,
    });

    const missing = await db.customers.get("c1");
    expect(missing.isErr() && missing.error).toBe("not_found");
  });

  it("converts $rpc, $table, $list and $from, and keeps db unchanged", async () => {
    const { client } = capturingClient((request) =>
      request.path.includes("/rpc/")
        ? { body: [{ id: "o1", name: "Acme" }] }
        : { body: [customer] },
    );

    const plain = betterSupabase.connect(client);
    const db = withBetterResult(plain, toResult);

    const organizations = await db.$rpc("my_organizations");
    expect(organizations.isOk() && organizations.value).toEqual([
      { id: "o1", name: "Acme" },
    ]);

    const counted = await db.$table("customers").list({ limit: 1 });
    expect(counted.isOk() && counted.value).toEqual([customer]);

    const list = defineListQuery(betterSupabase, "customers", {
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
      pageSize: 10,
    });

    const page = await db.$list(list, list.defaults);
    expect(page.isOk() && page.value.items).toEqual([customer]);

    const converted = await db.$from(
      AsyncResult.err(dbError("forbidden", "No")),
    );

    expect(converted.isErr() && converted.error).toBeInstanceOf(DbFailure);

    expect(db.$db).toBe(plain);
    expect(plain.customers.list()).toBeInstanceOf(AsyncResult);
    expect(db.customers).toBe(db.customers);
    expect(Object.keys(db)).toContain("customers");
  });

  it("wraps each repository once and passes plain values through", () => {
    const { client } = capturingClient();
    const db = withBetterResult(betterSupabase.connect(client), toResult);
    expect(db.$table("customers")).toBe(db.customers);
    expect(db.customers.$tableName).toBe("customers");
    expect(() => db.$table("nope" as "customers")).toThrow(TypeError);
  });
});
