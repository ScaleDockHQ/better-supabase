import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (
  names: readonly string[] = ["linked-identities"],
  layout: Parameters<typeof renderBlocks>[1] = {},
): string =>
  renderBlocks(names, layout)
    .filter((file) => file.module === "linked-identities")
    .map((file) => file.contents)
    .join("\n");

describe("identities module", () => {
  it("is registered after time-tracking", () => {
    const names = Object.keys(SQL_MODULES);
    expect(names.indexOf("linked-identities")).toBe(
      names.indexOf("time-tracking") + 1,
    );
  });

  it("lets users read and delete their own links and write none", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      'grant select, delete on "better_supabase"."identity_links" to authenticated;',
    );
    expect(sql).not.toMatch(/grant (insert|update)[^;]*identity_links/);
    expect(sql).toContain(
      'create policy "identity_links_own_read" on "better_supabase"."identity_links" for select to authenticated',
    );
    expect(sql).toContain(
      'create policy "identity_links_own_delete" on "better_supabase"."identity_links" for delete to authenticated',
    );
    expect(sql).not.toMatch(/create policy[^;]*for (insert|update)/);
    expect(sql).toContain("check (num_nonnulls(");
    expect(sql).toContain("unique nulls not distinct");
  });

  it("stores link codes hashed and redeems them as the service role only", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      `encode(extensions.digest(convert_to(v_code, 'utf8'), 'sha256'), 'hex')`,
    );
    expect(sql).not.toContain('"code" text');

    for (const signature of [
      "redeem_identity_link(text, text, text, text, text)",
      "principal_by_identity(text, text, text, text)",
      "link_verified_email(uuid)",
      "backfill_verified_emails()",
    ]) {
      expect(sql).toContain(
        `revoke execute on function "better_supabase"."${signature.split("(")[0]!}"(${signature.split("(")[1]!} from public, anon, authenticated;`,
      );
    }

    expect(sql).toContain(
      `revoke execute on function "better_supabase"."begin_identity_link"(text, text) from public, anon;`,
    );
    expect(sql).toContain("interval '10 minutes'");
    expect(sql).toContain(`and "used_at" is null`);
    expect(sql).toContain(`and "expires_at" > now()`);
  });

  it("clamps codeMinutes to 1..60", () => {
    const at = (codeMinutes: number): string =>
      sqlOf(["linked-identities"], {
        modules: { "linked-identities": { options: { codeMinutes } } },
      });

    expect(at(5)).toContain("interval '5 minutes'");
    expect(at(600)).toContain("interval '60 minutes'");
    expect(at(0)).toContain("interval '1 minutes'");
  });

  it("links confirmed addresses from auth.users unless verifiedEmails is off", () => {
    expect(sqlOf()).toContain(
      "after insert or update of email, email_confirmed_at on auth.users",
    );
    expect(sqlOf()).toContain("u.email_confirmed_at is not null");

    const off = sqlOf(["linked-identities"], {
      modules: { "linked-identities": { options: { verifiedEmails: false } } },
    });

    expect(off).toContain(
      'drop trigger if exists "bsb_identity_email" on auth.users;',
    );
    expect(off).not.toContain("create trigger");
  });

  it("references inbox contacts only when the inbox is installed", () => {
    expect(sqlOf()).not.toContain('references "better_supabase"."contacts"');
    expect(sqlOf(["inbox", "linked-identities"])).toContain(
      `"contact_id" uuid references "better_supabase"."contacts" ("id") on delete cascade`,
    );
  });

  it("installs in another schema", () => {
    const sql = sqlOf(["linked-identities"], {
      modules: { "linked-identities": { schema: "app_private" } },
    });

    expect(sql).toContain(
      'create table if not exists "app_private"."identity_links"',
    );
    expect(sql).toContain('"app_private"."begin_identity_link"');
  });
});
