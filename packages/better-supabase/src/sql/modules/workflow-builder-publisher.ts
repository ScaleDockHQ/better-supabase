import type { BuilderSql } from "./workflow-builder-sql.ts";

import { fail, serviceGrant } from "../shared.ts";

/**
 * `workflow_graph_permissions`, which publish stores, and
 * `workflow_run_principal`, which each step of a published version reads.
 */
export function builderPublisherSql(s: BuilderSql): string {
  const {
    id,
    fn,
    d,
    v,
    cd,
    cv,
    permission,
    nodeOperations,
    operationKeys,
    l,
    cl,
    userHolds,
    principal,
    callable,
  } = s;
  const revoked = (message: string): string =>
    `raise exception ${message}
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_REVOKED';`;
  return `-- The permissions the step nodes of graph need, sorted and distinct: the
-- provider's workflow.node.<step> operation, else the operation the library
-- step names (the provider's key for it, else the name itself), else
-- workflow.run. Trigger, sleep, approval and condition nodes need none.
create or replace function ${fn("workflow_graph_permissions")}(graph jsonb)
returns text[]
language sql
stable
set search_path = ''
as $$
  select coalesce(array_agg(distinct x.p order by x.p), '{}'::text[])
  from (
    select coalesce(
      ${nodeOperations} ->> (n.value ->> 'step'),
      (select coalesce(${operationKeys} ->> s.${cl("operation")}, s.${cl("operation")})
        from ${l} s where s.${cl("name")} = n.value ->> 'step'),
      ${permission("run")}
    ) as p
    from jsonb_array_elements(
      case when jsonb_typeof(workflow_graph_permissions.graph -> 'nodes') = 'array'
        then workflow_graph_permissions.graph -> 'nodes' else '[]'::jsonb end
    ) n
    where n.value ->> 'kind' = 'step'
  ) x;
$$;
${callable(`${fn("workflow_graph_permissions")}(jsonb)`)}

-- Whom the steps of a published or archived version run as (service role;
-- call it for every step). A user-owned version needs its publisher to
-- still hold workflow.publish and every stored permission in the tenant;
-- otherwise it raises WORKFLOW_PUBLISHER_REVOKED and the step fails. ${
    principal
      ? `An
-- organization-owned version runs as the tenant's default service
-- principal, which needs every stored permission through its role; without
-- one it raises WORKFLOW_PUBLISHER_REVOKED.`
      : `An
-- organization-owned version returns publisher null, for the app's service
-- principal.`
  } The trigger that started the run never changes the answer.
create or replace function ${fn("workflow_run_principal")}(version uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${v}%rowtype;
  v_tenant ${id};
  v_publisher uuid;
  v_missing text;
begin
  select * into v_row from ${v} x where x.${cv("id")} = version;
  if not found then
    ${fail("WORKFLOW_NOT_FOUND", "No such workflow version", "P0002")}
  end if;
  if v_row.${cv("status")} = 'draft' then
    ${fail("WORKFLOW_NOT_PUBLISHED", "This workflow version was never published", "P0002")}
  end if;
  select x.${cd("tenant")} into v_tenant from ${d} x where x.${cd("id")} = v_row.${cv("definition")};
  if v_row.${cv("owner")} is null then
    ${revoked("'This workflow version was published before publishers were recorded; publish it again'")}
  end if;
  if v_row.${cv("owner")} = 'user' then
    if v_row.${cv("publishedBy")} is null then
      ${revoked("'The user who published this workflow no longer exists'")}
    end if;
    select string_agg(p, ', ' order by p) into v_missing
    from unnest(array_append(v_row.${cv("permissions")}, ${permission("publish")})) p
    where not ${userHolds(`v_row.${cv("publishedBy")}`, "v_tenant", "p")};
    if v_missing is not null then
      ${revoked("'The user who published this workflow no longer holds %', v_missing")}
    end if;
  end if;
${
  principal
    ? `  if v_row.${cv("owner")} <> 'user' then
    v_publisher := ${principal("v_tenant")};
    if v_publisher is null then
      ${revoked("'This organization has no default service principal'")}
    end if;
    select string_agg(p, ', ' order by p) into v_missing
    from unnest(v_row.${cv("permissions")}) p
    where not ${userHolds("v_publisher", "v_tenant", "p")};
    if v_missing is not null then
      ${revoked("'The service principal no longer holds %', v_missing")}
    end if;
  end if;
`
    : ""
}  return jsonb_build_object(
    'publisher', coalesce(v_publisher, v_row.${cv("publishedBy")}),
    'tenant', v_tenant,
    'owner', v_row.${cv("owner")},
    'permissions', to_jsonb(v_row.${cv("permissions")})
  );
end;
$$;
${serviceGrant(`${fn("workflow_run_principal")}(uuid)`)}`;
}
