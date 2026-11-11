import { describe, expect, it } from "vitest";

import {
  applyIndexSkips,
  withoutSkippedIndexes,
} from "../../src/sql/index-skip.ts";
import { moduleFileVersion } from "../../src/sql/markers.ts";
import { renderBlocks } from "../../src/sql/render.ts";

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
