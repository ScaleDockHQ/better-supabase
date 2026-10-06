import { describe, expect, it } from "vitest";

import { policyGrants } from "../../src/sql/policy-grants.ts";

describe("policyGrants", () => {
  it("collects the permissive policies per table and role", () => {
    const grants = policyGrants(
      [
        {
          text: `create policy notes_read on public.notes for select to authenticated
  using (true);
-- create policy ignored on public.notes for delete to anon using (true);
create policy notes_write on notes for insert to authenticated with check (true);
create policy "Plans are public" on public."Plans" for select to anon, authenticated using (true);
create policy everyone on public.tags using (true);
create policy only_mfa on public.notes as restrictive for all to authenticated using (true);
create policy service on public.jobs for all to service_role using (true);
create policy internal on private.secrets for select to authenticated using (true);`,
        },
      ],
      ["public"],
    );
    expect(grants).toEqual([
      { table: "public.Plans", role: "anon", privileges: ["select"] },
      { table: "public.Plans", role: "authenticated", privileges: ["select"] },
      {
        table: "public.notes",
        role: "authenticated",
        privileges: ["select", "insert"],
      },
      {
        table: "public.tags",
        role: "authenticated",
        privileges: ["select", "insert", "update", "delete"],
      },
    ]);
  });
});
