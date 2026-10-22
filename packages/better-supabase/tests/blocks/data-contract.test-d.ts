import { describe, expectTypeOf, it } from "vitest";

import type { ClientOf } from "../../src/blocks/define-block.ts";
import type { AllBlocks } from "./all-blocks.ts";

/** The verbs the data contract replaced. */
type Retired =
  | "createMany"
  | "deleteMany"
  | "exists"
  | "findById"
  | "findFirst"
  | "findMany"
  | "findOnly"
  | "findUnique"
  | "forSubject"
  | "paginate"
  | "save"
  | "set"
  | "tag"
  | "untag"
  | "updateMany"
  | "upsertMany";

/** `"<block>.<method>"` for each retired verb on a client or a group in it. */
type RetiredOn<K extends string, C> = {
  readonly [M in keyof C & string]: M extends Retired
    ? `${K}.${M}`
    : C[M] extends (...args: never) => unknown
      ? never
      : C[M] extends object
        ? `${K}.${M}.${Extract<keyof C[M], Retired>}`
        : never;
}[keyof C & string];

type Offenders = {
  readonly [K in Extract<keyof AllBlocks, string>]: RetiredOn<
    K,
    ClientOf<AllBlocks[K]>
  >;
}[Extract<keyof AllBlocks, string>];

describe("the data contract", () => {
  it("leaves no retired verb on a block client", () => {
    expectTypeOf<Offenders>().toEqualTypeOf<never>();
  });
});
