import { describe, expect, it } from "vitest";

import { renderModules } from "../../src/sql/render.ts";

/** Each module whose managed table takes `extraColumns`, and what its SQL must show for a `region text` column. */
const CASES: readonly {
  readonly module: string;
  readonly table: string;
  /** The write: a key check or a populate from the input. */
  readonly writes: readonly string[];
  /** The read: where the column comes back. */
  readonly reads: readonly string[];
  /** A column the table already has. */
  readonly taken?: string;
}[] = [
  {
    module: "flags",
    table: "flags",
    taken: "key",
    writes: [`"region" = case when d -> 'fields' ? 'region'`],
    reads: [`'fields', jsonb_build_object('region', x."region")`],
  },
  {
    module: "hiring",
    table: "jobs",
    writes: [`"region" = case when save_job.attrs -> 'fields' ? 'region'`],
    reads: [
      `jsonb_build_object('fields', jsonb_build_object('region', v_job."region"))`,
    ],
  },
  {
    module: "deals",
    table: "deals",
    writes: [
      `"region" = case when create_deal.attrs ? 'region'`,
      "when 'region' then",
    ],
    reads: ["to_jsonb(x)"],
  },
  {
    module: "invoices",
    table: "invoices",
    writes: [`"region" = case when create_invoice.attrs ? 'region'`],
    reads: ["to_jsonb(x)"],
  },
];

const body = (module: string, options: Record<string, unknown>): string =>
  renderModules([module], { modules: { [module]: { options } } })
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("extraColumns", () => {
  it.each(CASES)(
    "$module adds, writes and returns the extra columns of $table",
    ({ module, writes, reads }) => {
      const sql = body(module, { extraColumns: { region: "text" } });
      expect(sql).toContain('add column if not exists "region" text;');
      for (const write of writes) expect(sql).toContain(write);
      for (const read of reads) expect(sql).toContain(read);
      expect(body(module, {})).not.toContain('"region"');
    },
  );

  it.each(CASES)("$module refuses a name it already uses", (entry) => {
    expect(() =>
      body(entry.module, { extraColumns: { [entry.taken ?? "id"]: "text" } }),
    ).toThrow(/shadows/);
  });
});
