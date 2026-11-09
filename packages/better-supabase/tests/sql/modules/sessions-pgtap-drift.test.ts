import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/render.ts";

const FILE = new URL(
  "../../../../../supabase/tests/database/bootstrap_provider_wrapper.test.sql",
  import.meta.url,
);

describe("supabase/tests/database/bootstrap_provider_wrapper.test.sql", () => {
  it("embeds the wrapper the sessions module renders for that provider", async () => {
    const sql = moduleBody("sessions", {
      modules: {
        sessions: { options: { bootstrap: { wrapper: "stubapp.page_data" } } },
      },
      accessProvider: {
        name: "stub",
        scope: "organization",
        idType: "uuid",
        functions: {
          idsWith: "a.b({permission})",
          isPlatform: "a.c({permission})",
          subject: "stubauthz.subject_for_caller",
          subjectForTenant: "stubauthz.subject_for(auth.uid(), {tenant})",
          bootstrapPermissions: "stubauthz.bootstrap_permissions({tenant})",
        },
      },
    })!;

    const start = sql.indexOf(
      "create or replace function better_supabase.bootstrap_wrapper",
    );

    const end = sql.indexOf(
      "to authenticated",
      sql.indexOf(
        "grant execute on function better_supabase.bootstrap_wrapper",
      ),
    );

    const rendered = sql.slice(start, end + "to authenticated".length);

    expect(start).toBeGreaterThan(-1);
    expect(await readFile(FILE, "utf-8")).toContain(`${rendered};`);
  });
});
