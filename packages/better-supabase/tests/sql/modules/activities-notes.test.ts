import { describe, expect, it } from "vitest";

import { customContracts, renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

const sqlOf = (
  options: Record<string, unknown> = {},
  extra: readonly string[] = [],
): string =>
  renderBlocks(["activities", ...extra], {
    subjects: { deal: { table: "public.deals" } },
    modules: { activities: { options } },
  })
    .filter((file) => file.module === "activities")
    .map((file) => file.contents)
    .join("\n");

async function run(
  options: Record<string, unknown>,
  check: string,
): Promise<void> {
  const files = renderBlocks(
    ["memberships", "permissions", "subjects", "activities"],
    { modules: { activities: { options } } },
  );

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
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

/** Runs `body` and raises unless it fails with `hint`. */
const fails = (body: string, hint: string): string => `
  begin
    ${body};
    raise exception 'no error' using hint = 'NONE';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint is distinct from '${hint}' then
      raise exception 'expected ${hint}, got % (%)', v_hint, sqlerrm;
    end if;
  end;`;

describe("progress notes, rendered", () => {
  it("adds the note columns, the addendum index and the functions", () => {
    const sql = sqlOf();

    expect(sql).toContain(
      `add column if not exists "audience" text not null default 'team' check ("audience" in ('team', 'subject', 'restricted'))`,
    );
    expect(sql).toContain(
      `add column if not exists "amends_id" uuid references "better_supabase"."engagements" ("id") on delete cascade`,
    );
    expect(sql).toContain(
      `create index if not exists engagements_amends_idx on "better_supabase"."engagements" ("amends_id")`,
    );
    expect(sql).toContain('function "better_supabase"."amend_engagement"');
    expect(sql).toContain('function "better_supabase"."mark_engagement_error"');
    expect(sql).toContain("interval '24 hours'");
    expect(sql).toContain("'{note,report}'::text[]");
    expect(sql).toContain("engagements.read_restricted");
    expect(sql).toContain('"better_supabase"."has_subject_role"');
    expect(sql).not.toContain("engagement_guest_readable");
  });

  it("takes the lock window, the locked types and the categories", () => {
    const sql = sqlOf({
      lockAfterHours: 2,
      lockTypes: ["note"],
      noteCategories: ["care", "medical"],
    });

    expect(sql).toContain("interval '2 hours'");
    expect(sql).toContain("'{note}'::text[]");
    expect(sql).toContain("'{care,medical}'::text[]");
    expect(sqlOf({ lockTypes: [] })).toContain("null::timestamptz");
  });

  it("rejects bad options", () => {
    expect(() => sqlOf({ lockAfterHours: -1 })).toThrow(/lockAfterHours/);
    expect(() => sqlOf({ lockAfterHours: 1.5 })).toThrow(/lockAfterHours/);
    expect(() => sqlOf({ noteCategories: ["Care"] })).toThrow(
      /lowercase names/,
    );
  });

  it("lets guests read subject notes with guests installed", () => {
    const sql = sqlOf({}, ["guests"]);

    expect(sql).toContain(
      'function "better_supabase"."engagement_guest_readable"',
    );
    expect(sql).toContain(
      `"audience" = 'subject' and "better_supabase"."engagement_guest_readable"("id")`,
    );
  });

  it("lists the note functions in the contract", () => {
    const names = customContracts(["activities"], {
      modules: { activities: { mode: "custom" } },
    })
      .find((contract) => contract.module === "activities")
      ?.functions.map((fn) => fn.name);

    expect(names).toEqual(
      expect.arrayContaining(["amend_engagement", "mark_engagement_error"]),
    );
  });

  it("needs the audience for restricted roles and the flag for its details", () => {
    const over = (columns: Record<string, null>) => () =>
      renderBlocks(["activities"], {
        modules: { activities: { columns: { engagements: columns } } },
      });

    expect(over({ audience: null })).toThrow(/restrictedRoles needs audience/);
    expect(over({ markedErrorAt: null })).toThrow(/need markedErrorAt/);
  });

  it("leaves the note columns and the audience check out when all map to null", () => {
    const sql = renderBlocks(["activities"], {
      modules: {
        activities: {
          columns: {
            engagements: {
              audience: null,
              restrictedRoles: null,
              category: null,
              lockedAt: null,
              amends: null,
              goal: null,
              markedErrorAt: null,
              markedErrorBy: null,
              markedErrorReason: null,
            },
          },
        },
      },
    })
      .filter((file) => file.module === "activities")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("-- Progress notes:");
    expect(sql).not.toContain("engagements.read_restricted");
  });
});

describe("progress notes, in Postgres", BOOT, () => {
  it("locks notes, takes addenda and flags errors", async () => {
    await expect(
      run(
        { lockAfterHours: 0 },
        `do $$
declare
  v_note jsonb;
  v_task jsonb;
  v_addendum jsonb;
  v_flagged jsonb;
  v_hint text;
begin
  ${SERVICE}
  v_note := better_supabase.log_engagement('${TENANT}', '{"type": "note", "title": "Shift", "body": "Calm", "category": "care", "audience": "subject"}'::jsonb, '[]'::jsonb);
  if v_note ->> 'locked_at' is null or v_note ->> 'audience' <> 'subject' or v_note ->> 'category' <> 'care' then
    raise exception 'logged %', v_note;
  end if;
  ${fails(`perform better_supabase.update_engagement((v_note ->> 'id')::uuid, '{"body": "Changed"}'::jsonb, null)`, "ENGAGEMENT_LOCKED")}
  ${fails(`perform better_supabase.delete_engagement((v_note ->> 'id')::uuid)`, "ENGAGEMENT_LOCKED")}
  ${fails(`perform better_supabase.log_engagement('${TENANT}', '{"type": "note", "title": "Bad", "category": "gossip"}'::jsonb, '[]'::jsonb)`, "ENGAGEMENT_CATEGORY_INVALID")}
  ${fails(`perform better_supabase.log_engagement('${TENANT}', '{"type": "note", "title": "Bad", "audience": "everyone"}'::jsonb, '[]'::jsonb)`, "ENGAGEMENT_AUDIENCE_INVALID")}
  ${fails(`perform better_supabase.amend_engagement((v_note ->> 'id')::uuid, ' ')`, "ENGAGEMENT_BODY_REQUIRED")}

  v_addendum := better_supabase.amend_engagement((v_note ->> 'id')::uuid, 'Also ate well');
  if v_addendum ->> 'amends_id' <> v_note ->> 'id' or v_addendum ->> 'body' <> 'Also ate well'
    or v_addendum ->> 'audience' <> 'subject' or v_addendum ->> 'category' <> 'care' then
    raise exception 'amended %', v_addendum;
  end if;

  v_task := better_supabase.log_engagement('${TENANT}', '{"type": "task", "title": "Call back"}'::jsonb, '[]'::jsonb);
  if v_task ->> 'locked_at' is not null then
    raise exception 'locked a task %', v_task;
  end if;
  ${fails(`perform better_supabase.mark_engagement_error((v_task ->> 'id')::uuid, '')`, "ENGAGEMENT_REASON_REQUIRED")}
  v_flagged := better_supabase.mark_engagement_error((v_task ->> 'id')::uuid, 'Wrong client');
  if v_flagged ->> 'marked_error_at' is null or v_flagged ->> 'marked_error_reason' <> 'Wrong client' or v_flagged ->> 'locked_at' is null then
    raise exception 'flagged %', v_flagged;
  end if;
  ${fails(`perform better_supabase.mark_engagement_error((v_task ->> 'id')::uuid, 'Again')`, "ENGAGEMENT_ALREADY_MARKED_ERROR")}
  ${fails(`perform better_supabase.complete_engagement((v_task ->> 'id')::uuid, true, null)`, "ENGAGEMENT_LOCKED")}
  if not exists (select 1 from better_supabase.engagements where id = (v_task ->> 'id')::uuid) then
    raise exception 'the flagged row is gone';
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });
});
