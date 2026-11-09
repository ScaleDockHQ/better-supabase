import { describe, expect, it } from "vitest";

import { duplicateObjects } from "../../src/sql/duplicate-objects.ts";

describe("duplicateObjects", () => {
  const block = (contents: string) => [{ contents }];
  const app = (text: string) => [{ text }];

  it("reports a block unique index an app unique index covers", () => {
    const found = duplicateObjects(
      block(
        `create unique index inventory_locations_id_organization_id_key on public.inventory_locations (id, organization_id);
create unique index invoices_key on public.invoices (organization_id, direction, kind, number);`,
      ),
      app(
        `create unique index locations_id_org on public.inventory_locations (id, organization_id);
create unique index invoices_number on public.invoices (organization_id, number);`,
      ),
      ["public"],
    );

    expect(found).toEqual([
      expect.objectContaining({
        kind: "index",
        block: "inventory_locations_id_organization_id_key",
        app: "locations_id_org",
        reason: "identical",
      }),
      expect.objectContaining({
        kind: "index",
        block: "invoices_key",
        app: "invoices_number",
        reason: "weaker",
      }),
    ]);
  });

  it("leaves partial indexes, other tables and other columns alone", () => {
    expect(
      duplicateObjects(
        block(
          `create unique index a on public.t (x, y);
create unique index b on public.u (x);
create unique index c on public.t (z) where z is not null;`,
        ),
        app(
          `create unique index mine on public.t (x, w);
create unique index mine2 on public.t (z) where z > 0;`,
        ),
        ["public"],
      ),
    ).toEqual([]);
  });

  it("reports a block updated_at trigger next to the app's track_updated_at", () => {
    const found = duplicateObjects(
      block(
        `create trigger notes_touch before update on public.notes for each row execute function better_supabase.set_updated_at();`,
      ),
      app(`select better_supabase.track_updated_at('public.notes');`),
      ["public"],
    );

    expect(found).toEqual([
      expect.objectContaining({
        kind: "trigger",
        table: "public.notes",
        block: "notes_touch",
      }),
    ]);
  });
});
