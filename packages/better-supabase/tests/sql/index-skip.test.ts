import { describe, expect, it } from "vitest";

import {
  applyIndexSkips,
  withoutRepeatedIndexes,
  withoutSkippedIndexes,
} from "../../src/sql/index-skip.ts";
import { moduleFileVersion } from "../../src/sql/markers.ts";
import { maskComments, statementSpans } from "../../src/sql/over-app-tables.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { indexSignature, indexStatements } from "../../src/sql/text-edit.ts";

const invoices = (skip?: readonly string[]): string =>
  renderBlocks(["invoices"], {
    modules: skip === undefined ? {} : { invoices: { indexes: { skip } } },
  })
    .filter((file) => file.module === "invoices" && file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");

describe("blocks.indexes.skip", () => {
  it("leaves out a named index and keeps the others", () => {
    const sql = invoices(["invoices_tenant_status_idx"]);

    expect(sql).not.toContain("invoices_tenant_status_idx");
    expect(sql).toContain("invoice_charges_invoice_idx");
  });

  it("refuses a name the module does not create", () => {
    expect(() => invoices(["invoices_tenant_status_due"])).toThrow(
      /invoices_tenant_status_due/,
    );
  });

  it("does not drop an index name that only appears inside a function", () => {
    const sql = `
create index if not exists kept_idx on public.kept (id);
create function public.note() returns void language sql as $$
  select 1 where false;
$$;
`;

    const stripped = withoutSkippedIndexes(sql, new Set(["note"]));

    expect(stripped.removed).toEqual([]);
    expect(stripped.sql).toContain("kept_idx");
    expect(stripped.sql).toContain("function public.note");
  });

  it("keeps the comments above a skipped index, such as the module header", () => {
    const sql = `-- better-supabase module: notifications
-- @bsb-block notifications@10
create index if not exists first_idx on public.events (subject);
create index if not exists kept_idx on public.events (actor);
`;

    const stripped = withoutSkippedIndexes(sql, new Set(["first_idx"]));

    expect(stripped.removed).toEqual(["first_idx"]);
    expect(stripped.sql).toBe(`-- better-supabase module: notifications
-- @bsb-block notifications@10

create index if not exists kept_idx on public.events (actor);
`);
  });

  it("keeps a module file's header and version when its first indexes are skipped", () => {
    const contents = `-- better-supabase module: notifications
-- @bsb-block notifications@10 managed

create index if not exists notification_events_subject_idx on public.notification_events (subject_id);
create index if not exists notification_events_actor_idx on public.notification_events (actor_id);
create index if not exists notification_events_kept_idx on public.notification_events (created_at);
`;

    const [file] = applyIndexSkips(
      [
        {
          module: "notifications",
          kind: "schema",
          path: "supabase/schemas/module_024_notifications.sql",
          contents,
        },
      ],
      () => [
        "notification_events_subject_idx",
        "notification_events_actor_idx",
      ],
    );

    expect(file?.contents).toMatch(
      /^-- better-supabase module: notifications\n-- @bsb-block notifications@10 managed\n/,
    );
    expect(moduleFileVersion(file?.contents ?? "")?.version).toBe(10);
    expect(file?.contents).not.toMatch(
      /notification_events_(?:subject|actor)_idx/,
    );
    expect(file?.contents).toContain("notification_events_kept_idx");
  });
});

describe("repeated indexes", () => {
  it("leaves out an index another name already builds, ignoring spelling", () => {
    const sql = `create index if not exists a_idx on public.t (owner_id);
create index if not exists b_idx on "public"."t" ("owner_id");
create index if not exists c_idx on public.t (owner_id) where owner_id is not null;
create unique index if not exists d_idx on public.t (owner_id);
create index if not exists e_idx on public.t using gin (owner_id);
create index if not exists a_idx on public.t (owner_id);
`;

    const out = withoutRepeatedIndexes(sql, new Map());

    expect(out).not.toContain("b_idx on");
    expect(out).toContain(
      "-- public.t already gets the same index as a_idx, so this block adds no b_idx.",
    );
    expect(out).toContain("c_idx on");
    expect(out).toContain("d_idx on");
    expect(out).toContain("e_idx on");
    expect(out.match(/a_idx on/g)).toHaveLength(2);
  });

  it("finds no two indexes of the same definition across every module", () => {
    const schema = renderBlocks(
      Object.keys(SQL_MODULES).filter((name) => name !== "pgtap"),
    ).filter((file) => file.kind === "schema");

    const seen = new Map<string, string>();
    const repeated: string[] = [];

    for (const file of schema) {
      const masked = maskComments(file.contents);

      expect(file.contents).not.toContain("already gets the same index as");

      for (const [from, to] of statementSpans(file.contents)) {
        const statement = masked.slice(from, to);

        const [index] = /^\s*create\s+(?:unique\s+)?index\b/i.test(statement)
          ? indexStatements(statement)
          : [];

        if (index?.name === undefined) {
          continue;
        }

        const signature = indexSignature(statement);
        const kept = seen.get(signature);

        if (kept !== undefined && kept !== index.name) {
          repeated.push(`${index.name} repeats ${kept}`);
        }

        seen.set(signature, kept ?? index.name);
      }
    }

    expect(seen.size).toBeGreaterThan(500);
    expect(repeated).toEqual([]);
  });
});
