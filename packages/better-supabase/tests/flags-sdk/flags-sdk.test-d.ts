import { flag } from "flags/next";
import { describe, expectTypeOf, it } from "vitest";

import type { FlagsSdkEntities } from "../../src/flags-sdk/index.ts";

import {
  betterSupabaseAdapter,
  createBetterSupabaseAdapter,
} from "../../src/flags-sdk/index.ts";

describe("flag() with the adapter", () => {
  it("type-checks when the factory is passed by reference", () => {
    const byReference = flag<boolean, FlagsSdkEntities>({
      key: "new_editor",
      adapter: betterSupabaseAdapter,
      defaultValue: false,
    });

    const called = flag<boolean, FlagsSdkEntities>({
      key: "new_editor",
      adapter: createBetterSupabaseAdapter()<boolean>(),
      defaultValue: false,
    });

    expectTypeOf(byReference).returns.toEqualTypeOf<Promise<boolean>>();
    expectTypeOf(called).returns.toEqualTypeOf<Promise<boolean>>();
  });
});
