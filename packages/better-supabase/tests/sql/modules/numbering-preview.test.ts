import { describe, expect, it } from "vitest";

import {
  ALICE,
  asMember,
  BOB,
  BOOT,
  entityPreviews,
  previews,
} from "../../fixtures/numbering.ts";

describe("preview_number", BOOT, () => {
  it("previews the tenant's next number under the assign permission", async () => {
    await expect(
      previews(`insert into public.invoices (organization_id, status, issued_on) values ('${ALICE}', 'sent', '2026-01-02');
${asMember(`do $$
begin
  if better_supabase.preview_number('${ALICE}', 'invoice', '2026-05-01') <> '2026-002' then
    raise exception 'previewed %', better_supabase.preview_number('${ALICE}', 'invoice', '2026-05-01');
  end if;
  if better_supabase.preview_number('${ALICE}', 'invoice', '2027-05-01') <> '2027-001' then
    raise exception 'previewed % for a new year', better_supabase.preview_number('${ALICE}', 'invoice', '2027-05-01');
  end if;
  if better_supabase.preview_number('${ALICE}', 'invoice', '2026-05-01') <> '2026-002' then
    raise exception 'a preview took the number';
  end if;
end;
$$;`)}`),
    ).resolves.toBeUndefined();
  });

  it("refuses a caller without the assign permission", async () => {
    await expect(
      previews(
        asMember(`select better_supabase.preview_number('${BOB}', 'invoice');`),
      ),
    ).rejects.toThrow(/not allowed to number documents/);
  });

  it("checks an entity's own permission and the block key for the others", async () => {
    await expect(
      entityPreviews(
        asMember(`do $$
begin
  if better_supabase.preview_number('${ALICE}', 'invoice', '2026-05-01') <> '2026-001' then
    raise exception 'previewed %', better_supabase.preview_number('${ALICE}', 'invoice', '2026-05-01');
  end if;
end;
$$;`),
      ),
    ).resolves.toBeUndefined();
    await expect(
      entityPreviews(
        asMember(`select better_supabase.preview_number('${ALICE}', 'quote');`),
      ),
    ).rejects.toThrow(/not allowed to number documents/);
  });
});
