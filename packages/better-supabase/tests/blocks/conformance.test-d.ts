import { describe, expectTypeOf, it } from "vitest";

import type { BlockOptions } from "../../src/core/block-helpers.ts";
import type { AllBlocks } from "./all-blocks.ts";

type OptionsOf<K extends keyof AllBlocks> =
  NonNullable<AllBlocks[K]["create"]> extends (options: infer O) => unknown
    ? O
    : BlockOptions;

/** The blocks whose creator's options are not `BlockOptions`. */
type NotBlockOptions = {
  readonly [K in keyof AllBlocks]: [OptionsOf<K>] extends [BlockOptions]
    ? never
    : K;
}[keyof AllBlocks];

/** Today's exceptions; shrink to `never`, never grow. */
type Allowed =
  | "idempotency"
  | "incomingWebhooks"
  | "organizations"
  | "rateLimit";

describe("the block contract", () => {
  it("passes BlockOptions to every creator", () => {
    expectTypeOf<NotBlockOptions>().toEqualTypeOf<Allowed>();
  });
});
