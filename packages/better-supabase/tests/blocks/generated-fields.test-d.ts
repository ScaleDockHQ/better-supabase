import { describe, expectTypeOf, it } from "vitest";

import type { GeneratedFields } from "../../src/blocks/block-config.ts";
import type { StandardSchemaV1 } from "../../src/core/standard.ts";

type Entry = {
  readonly schema: string;
  readonly options: Record<string, never>;
  readonly columns: {
    readonly cost_code: "text not null default 'none'";
    readonly ledger_ref: "text not null";
    readonly hint_text: "text";
  };
};

type Input = StandardSchemaV1.InferInput<GeneratedFields<Entry>["fields"]>;

describe("generated block fields", () => {
  it("requires a not null column without a default on insert", () => {
    expectTypeOf<Input["ledger_ref"]>().toEqualTypeOf<string>();
  });

  it("lets a not null column with a default and a nullable column be missing", () => {
    expectTypeOf<Input>().toMatchTypeOf<{ ledger_ref: string }>();
    expectTypeOf<{ ledger_ref: string }>().toMatchTypeOf<Input>();
  });

  it("adds nothing for an entry without columns", () => {
    expectTypeOf<
      GeneratedFields<{ readonly schema: string; readonly options: Record<string, unknown> }>
    >().toEqualTypeOf<unknown>();
  });
});
