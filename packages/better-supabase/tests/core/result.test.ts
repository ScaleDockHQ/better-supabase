import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import {
  type DbError,
  DbException,
  dbError,
  dbErrorOf,
  isConflict,
  mapDbError,
} from "../../src/core/errors.ts";
import {
  AsyncResult,
  defineBetterResultErrors,
  err,
  fromBetterResult,
  ok,
  toBetterResult,
  toDbError,
} from "../../src/core/result.ts";
import { settle } from "../../src/server/respond.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

class StandInOk<T> {
  readonly status = "ok";
  readonly value: T;
  constructor(value: T) {
    this.value = value;
  }
}

class StandInErr<E> {
  readonly status = "error";
  readonly error: E;
  constructor(error: E) {
    this.error = error;
  }
}

const Result = {
  ok: <T>(value: T) => new StandInOk(value),
  err: <E>(error: E) => new StandInErr(error),
};

class AppError extends Error {
  readonly error: DbError;
  constructor(error: DbError) {
    super(`app: ${error.message}`, { cause: error });
    this.error = error;
  }
}

const toAppError = (error: DbError) => new AppError(error);

const conflict = () =>
  capturingClient(() => ({
    status: 409,
    body: { code: "23505", message: "duplicate key value" },
  }));

describe("betterSupabase.mapError", () => {
  it("makes .orThrow() throw the mapped error; results keep the DbError", async () => {
    const db = defineSupabase(schema)
      .mapError(toAppError)
      .connect(conflict().client);

    const result = await db.customers.create({
      name: "Acme",
      organizationId: "o1",
    });

    expect(result.ok).toBe(false);
    expect(result.error?.kind).toBe("conflict");

    const thrown = await db.customers
      .create({ name: "Acme", organizationId: "o1" })
      .orThrow()
      .catch((error: unknown) => error);

    expect(thrown).toBeInstanceOf(AppError);
    expect((thrown as AppError).error.kind).toBe("conflict");
  });

  it("survives map, mapError and andThen, and a factory still wins", async () => {
    const db = defineSupabase(schema)
      .mapError(toAppError)
      .connect(conflict().client);

    const chained = db.customers
      .create({ name: "Acme", organizationId: "o1" })
      .map((row) => row.id)
      .mapError((error) => ({ ...error, message: "renamed" }))
      .andThen((id) => AsyncResult.ok(id));

    await expect(chained.orThrow()).rejects.toThrow("app: renamed");
    await expect(
      db.customers
        .create({ name: "Acme", organizationId: "o1" })
        .orThrow(() => new Error("factory")),
    ).rejects.toThrow("factory");
  });

  it("keeps the DbError reachable through cause for adapters and guards", async () => {
    const db = defineSupabase(schema)
      .mapError(toAppError)
      .connect(conflict().client);

    const thrown: unknown = await db.customers
      .create({ name: "Acme", organizationId: "o1" })
      .orThrow()
      .catch((error: unknown) => error);

    expect(dbErrorOf(thrown)?.kind).toBe("conflict");
    expect(isConflict(thrown)).toBe(true);

    const settled = await settle(() =>
      db.customers.create({ name: "Acme", organizationId: "o1" }).orThrow(),
    );

    expect(!settled.ok && settled.error.kind).toBe("conflict");
  });

  it("throws a DbException without a mapper", async () => {
    const db = defineSupabase(schema).connect(conflict().client);
    await expect(
      db.customers.create({ name: "Acme", organizationId: "o1" }).orThrow(),
    ).rejects.toBeInstanceOf(DbException);
  });
});

describe("toBetterResult", () => {
  it("builds Ok and Err with the namespace passed in", () => {
    const good = toBetterResult(ok(1), Result);
    expect(good).toBeInstanceOf(StandInOk);
    expect(good).toMatchObject({ status: "ok", value: 1 });

    const failure = dbError("not_found", "gone");
    expect(toBetterResult(err(failure), Result)).toMatchObject({
      status: "error",
      error: failure,
    });
    const mapped = toBetterResult(err(failure), Result, toAppError);
    expect(mapped.status === "error" && mapped.error).toBeInstanceOf(AppError);
  });

  it("awaits an AsyncResult and uses the mapper of betterSupabase.mapError", async () => {
    const db = defineSupabase(schema)
      .mapError(toAppError)
      .connect(conflict().client);

    const mapped = await toBetterResult(
      db.customers.create({ name: "Acme", organizationId: "o1" }),
      Result,
    );

    expect(mapped.status === "error" && mapped.error).toBeInstanceOf(AppError);

    const plain = await toBetterResult(AsyncResult.ok("x"), Result);
    expect(plain).toMatchObject({ status: "ok", value: "x" });
  });
});

describe("fromBetterResult", () => {
  it("converts by status and keeps DbErrors", () => {
    expect(fromBetterResult(Result.ok(2))).toEqual(ok(2));
    const failure = dbError("conflict", "taken");
    expect(fromBetterResult(Result.err(failure))).toEqual(err(failure));
  });

  it("turns other errors into DbErrors", () => {
    const converted = fromBetterResult(Result.err(new Error("boom")));
    expect(converted.error).toMatchObject({
      kind: "unexpected",
      message: "boom",
    });

    const custom = fromBetterResult(Result.err("nope"), () =>
      dbError("forbidden", "mapped"),
    );

    expect(custom.error?.kind).toBe("forbidden");
  });

  it("round-trips", () => {
    const original = ok({ id: "c1" });
    expect(fromBetterResult(toBetterResult(original, Result))).toEqual(
      original,
    );
  });
});

describe("toDbError", () => {
  it("classifies PostgREST error objects like mapDbError", () => {
    const raw = {
      code: "23505",
      message:
        'duplicate key value violates unique constraint "customers_email_key"',
      details: "Key (email)=(a@b.co) already exists.",
      hint: null,
    };

    expect(toDbError(raw)).toEqual(mapDbError(raw));
    expect(toDbError(raw)).toMatchObject({
      kind: "conflict",
      constraint: "customers_email_key",
      columns: ["email"],
    });
  });

  it.each([
    ["PGRST116", "JSON object requested, 0 rows returned", "not_found"],
    ["42501", "new row violates row-level security policy", "forbidden"],
    ["23514", 'violates check constraint "price_positive"', "check"],
    [
      "23503",
      'violates foreign key constraint "orders_customer_fkey"',
      "foreign_key",
    ],
  ])("maps code %s to %s", (code, message, kind) => {
    expect(toDbError({ code, message, details: null, hint: null }).kind).toBe(
      kind,
    );
  });

  it("classifies a thrown PostgrestError", () => {
    const thrown = Object.assign(new Error("duplicate key"), {
      name: "PostgrestError",
      code: "23505",
      details: "",
      hint: "",
    });

    expect(toDbError(thrown).kind).toBe("conflict");
  });

  it("keeps DbErrors and DbExceptions", () => {
    const failure = dbError("conflict", "taken");

    expect(toDbError(failure)).toBe(failure);
    expect(toDbError(new DbException(failure))).toBe(failure);
  });

  it("keeps other errors and unknown values unexpected", () => {
    const withCode = Object.assign(new Error("connect failed"), {
      code: "ECONNREFUSED",
    });

    const aborted = Object.assign(new Error("stop"), { name: "AbortError" });

    expect(toDbError(withCode)).toMatchObject({
      kind: "unexpected",
      message: "connect failed",
    });
    expect(toDbError(aborted).kind).toBe("aborted");
    expect(toDbError("nope")).toMatchObject({
      kind: "unexpected",
      message: "nope",
    });
    expect(toDbError({ message: "no code" }).kind).toBe("unexpected");
    expect(toDbError(null).kind).toBe("unexpected");
  });
});

class NotFound {
  readonly _tag = "NotFound";
  readonly message: string;
  readonly error: DbError;
  constructor(props: { message: string; error: DbError }) {
    this.message = props.message;
    this.error = props.error;
  }
}

class DbFailure {
  readonly _tag = "DbFailure";
  readonly message: string;
  constructor(props: { message: string }) {
    this.message = props.message;
  }
}

describe("defineBetterResultErrors", () => {
  const toResult = defineBetterResultErrors(
    Result,
    { not_found: NotFound },
    DbFailure,
  );

  it("maps each kind to its class and the rest to the fallback", () => {
    const missing = dbError("not_found", "No customer c1");
    const mapped = toResult.map(missing);
    expect(mapped).toBeInstanceOf(NotFound);
    expect(mapped).toMatchObject({ message: "No customer c1", error: missing });
    expect(toResult.map(dbError("forbidden", "Not yours"))).toBeInstanceOf(
      DbFailure,
    );
  });

  it("converts sync and async results", async () => {
    expect(toResult(ok(1))).toEqual(new StandInOk(1));
    const failed = toResult(err(dbError("not_found", "gone")));
    expect(failed).toBeInstanceOf(StandInErr);
    expect((failed as StandInErr<unknown>).error).toBeInstanceOf(NotFound);
    const later = await toResult(AsyncResult.err(dbError("conflict", "dup")));
    expect((later as StandInErr<unknown>).error).toBeInstanceOf(DbFailure);
    expect(await toResult(AsyncResult.ok("x"))).toEqual(new StandInOk("x"));
  });
});
