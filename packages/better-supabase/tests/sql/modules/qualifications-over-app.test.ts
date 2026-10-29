import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const USER = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own certifications, requirements and holdings: renamed columns
// and no description, timestamps, revoke reason, note or granter.
const APP = `
create table public.certifications (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  slug text not null,
  title text not null,
  applies_to text[] not null,
  months integer,
  needs_proof boolean not null default false,
  archived_at timestamptz
);

create table public.certification_rules (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  certification_id uuid not null references public.certifications (id) on delete cascade,
  kind text not null,
  value text not null
);

create table public.certificates_held (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  certification_id uuid not null references public.certifications (id) on delete cascade,
  holder_kind text not null,
  holder text not null,
  issued_on date not null,
  valid_until date,
  revoked_at timestamptz,
  proof_id uuid,
  origin text not null default 'manual',
  origin_id text,
  reported text
);
`;

const BLOCKS: AnyBlocksConfig = {
  qualifications: {
    tables: {
      types: "public.certifications",
      requirements: "public.certification_rules",
      qualifications: "public.certificates_held",
    },
    columns: {
      types: {
        tenant: "org_id",
        key: "slug",
        name: "title",
        holderTypes: "applies_to",
        validForMonths: "months",
        evidenceRequired: "needs_proof",
        description: null,
        course: null,
        createdAt: null,
        updatedAt: null,
      },
      requirements: {
        tenant: "org_id",
        type: "certification_id",
        targetType: "kind",
        targetValue: "value",
        createdAt: null,
      },
      qualifications: {
        tenant: "org_id",
        type: "certification_id",
        holderType: "holder_kind",
        holderId: "holder",
        grantedOn: "issued_on",
        expiresOn: "valid_until",
        evidenceAttachment: "proof_id",
        source: "origin",
        sourceId: "origin_id",
        notifiedStatus: "reported",
        revokeReason: null,
        evidenceNote: null,
        grantedBy: null,
        createdAt: null,
        updatedAt: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["qualifications"], {
    modules: BLOCKS,
    ownTables: {
      "public.certifications": "app.sql",
      "public.certification_rules": "app.sql",
      "public.certificates_held": "app.sql",
    },
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      APP,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("qualifications over the app's tables", BOOT, () => {
  it("saves types and requirements, grants, reports gaps and revokes", async () => {
    await expect(
      run(`do $$
declare
  v_type jsonb;
  v_held jsonb;
  v_gaps jsonb;
begin
  ${SERVICE}
  insert into auth.users (id, email) values ('${USER}', 'ada@example.com');
  insert into better_supabase.memberships (organization_id, user_id, role) values ('${TENANT}', '${USER}', 'member');
  v_type := better_supabase.save_qualification_type('${TENANT}', 'forklift', 'Forklift licence', array['member'], 12);
  perform better_supabase.save_qualification_type('${TENANT}', 'forklift', 'Forklift licence B', array['member'], 12);
  if (select count(*) from public.certifications) <> 1 or (select title from public.certifications) <> 'Forklift licence B' then
    raise exception 'type %', v_type;
  end if;
  perform better_supabase.add_qualification_requirement((v_type ->> 'id')::uuid, 'role', 'member');
  perform better_supabase.add_qualification_requirement((v_type ->> 'id')::uuid, 'role', 'member');
  if (select count(*) from public.certification_rules) <> 1 then
    raise exception 'requirements';
  end if;
  v_gaps := better_supabase.qualification_gaps('${TENANT}');
  if jsonb_array_length(v_gaps) <> 1 or v_gaps -> 0 ->> 'status' <> 'missing' or v_gaps -> 0 ->> 'holderTitle' <> 'ada@example.com' then
    raise exception 'gaps %', v_gaps;
  end if;
  v_held := better_supabase.grant_qualification('${TENANT}', 'forklift', 'member', '${USER}', current_date - 360);
  if v_held ->> 'status' <> 'expiring' or v_held ->> 'source' <> 'manual' then
    raise exception 'held %', v_held;
  end if;
  v_gaps := better_supabase.qualification_gaps('${TENANT}', 'member', '{"status": "expiring"}');
  if jsonb_array_length(v_gaps) <> 1 then
    raise exception 'expiring %', v_gaps;
  end if;
  if better_supabase.qualified_holders('${TENANT}', 'forklift') <> jsonb_build_array('${USER}') then
    raise exception 'holders %', better_supabase.qualified_holders('${TENANT}', 'forklift');
  end if;
  if better_supabase.notify_expiring_qualifications() <> 1 or better_supabase.notify_expiring_qualifications() <> 0 then
    raise exception 'notified twice';
  end if;
  perform better_supabase.revoke_qualification((v_held ->> 'id')::uuid, 'Failed the check');
  if better_supabase.qualified_holders('${TENANT}', 'forklift') <> '[]'::jsonb then
    raise exception 'still qualified';
  end if;
  v_gaps := better_supabase.qualification_gaps('${TENANT}', 'member', jsonb_build_object('holderId', '${USER}'));
  if v_gaps -> 0 ->> 'status' <> 'missing' then
    raise exception 'after revoke %', v_gaps;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
