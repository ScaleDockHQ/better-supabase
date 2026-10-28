import { describe, expect, it } from "vitest";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";
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
create schema if not exists extensions;
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(
    ["memberships", "permissions", "workflows", "workflow-editor"],
    {},
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

describe("workflow-editor node kinds and purposes", () => {
  it("renders the registry, its functions and the purpose columns", () => {
    const body = moduleBody("workflow-editor", {})!;

    expect(body).toContain(
      'create table if not exists "better_supabase"."workflow_node_kinds"',
    );
    expect(body).toContain('"sync_workflow_node_kinds"(kinds jsonb)');
    expect(body).toContain('"set_workflow_definition_purpose"(');
    expect(body).toContain('"resolve_workflow_definition"(');
    expect(body).toContain(`"purpose" text not null default 'automation'`);
    expect(body).toContain("takes a branch from a node that does not branch");
  });

  it("syncs node kinds and validates graphs that use them", BOOT, async () => {
    await expect(
      run(`do $$
declare
  v_errors jsonb;
begin
  ${SERVICE}
  if better_supabase.sync_workflow_node_kinds('{"notify": {"title": "Notify"}, "score.check": {"title": "Score", "branches": true}}'::jsonb) <> 2 then
    raise exception 'sync';
  end if;
  if jsonb_array_length(better_supabase.workflow_node_kinds_list()) <> 2
    or not (better_supabase.workflow_node_kinds_list() -> 1 ->> 'branches')::boolean then
    raise exception 'list %', better_supabase.workflow_node_kinds_list();
  end if;
  v_errors := better_supabase.validate_workflow_graph('{"nodes": [
    {"id": "start", "kind": "trigger"},
    {"id": "check", "kind": "score.check"},
    {"id": "ping", "kind": "notify"},
    {"id": "bogus", "kind": "nope"}
  ], "edges": [
    {"id": "e1", "source": "start", "target": "check"},
    {"id": "e2", "source": "check", "target": "ping", "branch": "true"},
    {"id": "e3", "source": "ping", "target": "bogus", "branch": "false"}
  ]}'::jsonb);
  if v_errors <> '["Node bogus has an unknown kind", "Edge e3 takes a branch from a node that does not branch"]'::jsonb then
    raise exception 'errors %', v_errors;
  end if;
  if better_supabase.sync_workflow_node_kinds('{"notify": {"title": "Notify"}}'::jsonb) <> 1 then
    raise exception 'resync';
  end if;
  begin
    perform better_supabase.sync_workflow_node_kinds('[]'::jsonb);
    raise exception 'array accepted';
  exception when others then
    if sqlerrm = 'array accepted' then
      raise;
    end if;
  end;
  begin
    perform better_supabase.sync_workflow_node_kinds('{"step": {"title": "Step"}}'::jsonb);
    raise exception 'built-in accepted';
  exception when check_violation then
    null;
  end;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("marks a lifecycle default per tenant and resolves it", BOOT, async () => {
    await expect(
      run(`do $$
declare
  v_first uuid;
  v_second uuid;
  v_auto uuid;
  v_draft jsonb;
  v_resolved jsonb;
  v_def jsonb;
begin
  ${SERVICE}
  v_first := (better_supabase.save_workflow_definition('${TENANT}', 'deal-a', 'Deal A', null, array['deal']) ->> 'id')::uuid;
  v_second := (better_supabase.save_workflow_definition('${TENANT}', 'deal-b', 'Deal B', null, array['deal']) ->> 'id')::uuid;
  v_auto := (better_supabase.save_workflow_definition('${TENANT}', 'auto', 'Auto') ->> 'id')::uuid;
  for v_draft in
    select better_supabase.save_workflow_draft(x, '{"nodes": [{"id": "start", "kind": "trigger"}], "edges": []}'::jsonb)
    from unnest(array[v_first, v_second]) x
  loop
    perform better_supabase.publish_workflow_version((v_draft ->> 'id')::uuid);
  end loop;
  if better_supabase.resolve_workflow_definition('${TENANT}') is not null then
    raise exception 'resolved without a default';
  end if;
  v_def := better_supabase.set_workflow_definition_purpose(v_first, 'lifecycle', true);
  if v_def ->> 'purpose' <> 'lifecycle' or not (v_def ->> 'isDefault')::boolean then
    raise exception 'set %', v_def;
  end if;
  v_resolved := better_supabase.resolve_workflow_definition('${TENANT}', 'lifecycle', 'deal');
  if (v_resolved -> 'definition' ->> 'id')::uuid <> v_first or v_resolved -> 'version' ->> 'status' <> 'published' then
    raise exception 'resolved %', v_resolved;
  end if;
  if better_supabase.resolve_workflow_definition('${TENANT}', 'lifecycle', 'ticket') is not null then
    raise exception 'resolved another subject type';
  end if;
  perform better_supabase.set_workflow_definition_purpose(v_second, 'lifecycle', true);
  if (select is_default from better_supabase.workflow_definitions where id = v_first) then
    raise exception 'first default kept';
  end if;
  if (better_supabase.resolve_workflow_definition('${TENANT}') -> 'definition' ->> 'id')::uuid <> v_second then
    raise exception 'second not resolved';
  end if;
  begin
    perform better_supabase.set_workflow_definition_purpose(v_auto, 'automation', true);
    raise exception 'automation default accepted';
  exception when others then
    if sqlerrm = 'automation default accepted' then
      raise;
    end if;
  end;
  begin
    perform better_supabase.set_workflow_definition_purpose(v_auto, 'lifecycle');
    raise exception 'lifecycle without subject types accepted';
  exception when others then
    if sqlerrm = 'lifecycle without subject types accepted' then
      raise;
    end if;
  end;
  begin
    perform better_supabase.set_workflow_definition_purpose(v_auto, 'other');
    raise exception 'unknown purpose accepted';
  exception when others then
    if sqlerrm = 'unknown purpose accepted' then
      raise;
    end if;
  end;
  begin
    perform better_supabase.set_workflow_definition_purpose(gen_random_uuid(), 'automation');
    raise exception 'missing definition accepted';
  exception when others then
    if sqlerrm = 'missing definition accepted' then
      raise;
    end if;
  end;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
