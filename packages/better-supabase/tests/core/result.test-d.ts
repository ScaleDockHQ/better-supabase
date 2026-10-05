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

  it("still accepts a cast to the better-result type", () => {
    const value = toBetterResult(result, Br);
    const typed = value as BrResult<{ id: string }, DbError>;
    expectTypeOf(typed.map((row) => row.id)).toEqualTypeOf<
      BrResult<string, DbError>
    >();
  });

  it("takes the better-result type from the expected type", () => {
    const typed: BrResult<{ id: string }, AppError> = toBetterResult(
      result,
      Br,
      () => new AppError(),
    );
    expectTypeOf(typed.map((row) => row.id)).toEqualTypeOf<
      BrResult<string, AppError>
    >();
    const plain: BrResult<{ id: string }, DbError> = toBetterResult(result, Br);
    expectTypeOf(plain).toEqualTypeOf<BrResult<{ id: string }, DbError>>();
  });

  it("takes the better-result type as a type argument", () => {
    expectTypeOf(
      toBetterResult<BrResult<{ id: string }, AppError>>(
        result,
        Br,
        () => new AppError(),
      ),
    ).toEqualTypeOf<BrResult<{ id: string }, AppError>>();
    expectTypeOf(
      toBetterResult<BrResult<number, AppError>>(
        AsyncResult.ok(1),
        Br,
        () => new AppError(),
      ),
    ).toEqualTypeOf<Promise<BrResult<number, AppError>>>();
    expectTypeOf(
      toBetterResult<BrResult<number, unknown>>(AsyncResult.ok(1), Br),
    ).toEqualTypeOf<Promise<BrResult<number, unknown>>>();
  });

  it("types a function's return value without a cast", () => {
    const load = async (): Promise<BrResult<number, AppError>> =>
      toBetterResult(AsyncResult.ok(1), Br, () => new AppError());
    const generic = <T>(value: Result<T>): BrResult<T, AppError> =>
      toBetterResult(value, Br, () => new AppError());
    expectTypeOf(load).returns.resolves.toEqualTypeOf<
      BrResult<number, AppError>
    >();
    expectTypeOf(generic(result)).toEqualTypeOf<
      BrResult<{ id: string }, AppError>
    >();
  });

  it("checks the expected type against the row and the error", () => {
    // @ts-expect-error the row is { id: string }, not string
    const wrongRow: BrResult<string, AppError> = toBetterResult(
      result,
      Br,
      () => new AppError(),
    );
    // @ts-expect-error mapError returns AppError, not string
    const wrongError: BrResult<{ id: string }, string> = toBetterResult(
      result,
      Br,
      () => new AppError(),
    );
    // @ts-expect-error without mapError the error is a DbError
    const unmapped: BrResult<{ id: string }, AppError> = toBetterResult(
      result,
      Br,
    );
    // @ts-expect-error a mapper set with betterSupabase.mapError is typed unknown
    const carried: Promise<BrResult<number, AppError>> = toBetterResult(
      AsyncResult.ok(1),
      Br,
    );
    expectTypeOf([wrongRow, wrongError, unmapped, carried]).not.toBeNever();
  });
});

describe("fromBetterResult", () => {
  it("returns a Result with DbError", () => {
    expectTypeOf(fromBetterResult(Br.ok(ok(1).data))).toEqualTypeOf<
      Result<number>
    >();
  });
});
