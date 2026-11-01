import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { createFlags } from "../../../src/blocks/flags/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const FLAG = {
  key: "beta",
  type: "boolean",
  variants: { on: true, off: false },
  default_variant: "off",
  enabled: true,
  rules: [],
  rollout_percentage: 0,
  rollout_variants: [],
  overrides: [],
  fields: { owner: "ana@acme.test" },
};

const Fields = v.object({ owner: v.pipe(v.string(), v.email()) });

describe("flags fields", () => {
  it("sends the extra fields under fields and parses them on reads", async () => {
    const t = fieldsTransport({
      save_flag: () => FLAG,
      list_flags: () => [FLAG, { ...FLAG, key: "plain", fields: undefined }],
    });

    const flags = createFlags({ transport: t, fields: v.partial(Fields) });

    const saved = await flags
      .upsert({
        key: "beta",
        input: { enabled: true, fields: { owner: "ana@acme.test" } },
      })
      .orThrow();

    expect(saved?.fields.owner).toBe("ana@acme.test");
    expect(t.calls[0]?.[1]).toEqual({
      key: "beta",
      definition: { enabled: true, fields: { owner: "ana@acme.test" } },
    });
    const list = await flags.list().orThrow();
    expect(list.map((flag) => flag.fields)).toEqual([
      { owner: "ana@acme.test" },
      {},
    ]);
  });

  it("refuses a bad field before the call", async () => {
    const t = fieldsTransport({ save_flag: () => FLAG });

    const saved = await createFlags({ transport: t, fields: Fields }).upsert({
      key: "beta",
      input: { fields: { owner: "not an email" } },
    });

    expect(saved.ok ? undefined : saved.error.kind).toBe("validation");
    expect(t.calls).toEqual([]);
  });
});
