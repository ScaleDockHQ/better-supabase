import { describe, expectTypeOf, it } from "vitest";

import type { DbError } from "../../src/core/errors.ts";

import {
  AsyncResult,
  type BetterResultValue,
  fromBetterResult,
  ok,
  type Result,
  toBetterResult,
} from "../../src/core/result.ts";

declare class BrOk<T, E = never> {
  readonly status: "ok";
  readonly value: T;
  map<U>(fn: (value: T) => U): BrResult<U, E>;
}
declare class BrErr<T, E> {
  readonly status: "error";
  readonly error: E;
  map<U>(fn: (value: T) => U): BrResult<U, E>;
}
type BrResult<T, E> = BrOk<T, E> | BrErr<T, E>;
declare const Br: {
  ok<T>(value: T): BrOk<T>;
  err<E>(error: E): BrErr<never, E>;
};

class AppError extends Error {}
declare const result: Result<{ id: string }>;

describe("toBetterResult", () => {
  it("types value and error", () => {
    expectTypeOf(toBetterResult(result, Br)).toEqualTypeOf<
      BetterResultValue<{ id: string }, DbError>
    >();
    expectTypeOf(
      toBetterResult(result, Br, () => new AppError()),
    ).toEqualTypeOf<BetterResultValue<{ id: string }, AppError>>();
  });

  it("types a mapper carried by betterSupabase.mapError as unknown", () => {
    expectTypeOf(toBetterResult(AsyncResult.ok(1), Br)).toEqualTypeOf<
      Promise<BetterResultValue<number, unknown>>
    >();
  });

  it("casts to the better-result type", () => {
    const value = toBetterResult(result, Br);
    const typed = value as BrResult<{ id: string }, DbError>;
    expectTypeOf(typed.map((row) => row.id)).toEqualTypeOf<
      BrResult<string, DbError>
    >();
  });
});

describe("fromBetterResult", () => {
  it("returns a Result with DbError", () => {
    expectTypeOf(fromBetterResult(Br.ok(ok(1).data))).toEqualTypeOf<
      Result<number>
    >();
  });
});
