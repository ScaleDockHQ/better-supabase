import type { AgentsEvents } from "../../blocks/agents/events.ts";
import type {
  BlockSqlContext,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { Columns } from "./module-columns.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  withExtraFields,
  raise,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
  revokeTable,
  writeExtraColumns,
} from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

const AGENTS = {
  id: "id",
  tenant: "organization_id",
  owner: "owner_id",
  slug: "slug",
  name: "name",
  description: "description",
  instructions: "instructions",
  model: "model",
  tools: "tools",
  connectors: "connector_ids",
  knowledgeScope: "knowledge_scope",
  starters: "starters",
  visibility: "visibility",
  publishedAt: "published_at",
  installCount: "install_count",
  ratingCount: "rating_count",
  ratingSum: "rating_sum",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const INSTALLS = {
  agent: "agent_id",
  user: "user_id",
  tenant: "organization_id",
  installedAt: "installed_at",
} as const;

const RATINGS = {
  agent: "agent_id",
  user: "user_id",
  rating: "rating",
  comment: "comment",
  createdAt: "created_at",
} as const;

const SKILLS = {
  id: "id",
  agent: "agent_id",
  provider: "provider",
  reference: "reference",
  createdAt: "created_at",
} as const;

const EVENTS: BlockSqlEvents<AgentsEvents> = {
  "agent.saved": {
    subject: "organizations",
    payload: ["organizationId", "agentId", "slug"],
  },
  "agent.published": {
    subject: "organizations",
    payload: ["organizationId", "agentId", "slug", "visibility"],
  },
  "agent.deleted": {
    subject: "organizations",
    payload: ["organizationId", "agentId", "slug"],
  },
  "agent.uninstalled": {
    subject: "organizations",
    payload: ["organizationId", "agentId", "userId"],
  },
  "agent.installed": {
    subject: "organizations",
    payload: ["organizationId", "agentId", "userId"],
  },
};

const NAMES: BlockSqlNames = {
  entities: { agent: { table: "agents", singular: "agent", primary: true } },
  events: EVENTS,
  options: ["maxInstructions", "extraColumns"],
  tables: {
    agents: {
      name: "agents",
      columns: AGENTS,
      lifecycle: { user: "owner", tenant: "tenant" },
      app: {},
      optional: [
        "description",
        "model",
        "tools",
        "connectors",
        "knowledgeScope",
        "starters",
        "installCount",
        "ratingCount",
        "ratingSum",
        "createdAt",
      ],
      typed: ["visibility"],
    },
    installs: {
      name: "agent_installs",
      columns: INSTALLS,
      lifecycle: { user: "user", tenant: "tenant" },
      app: {},
      optional: ["installedAt"],
    },
    ratings: {
      name: "agent_ratings",
      columns: RATINGS,
      lifecycle: { user: "user" },
      app: {},
      optional: ["comment", "createdAt"],
    },
    skills: {
      name: "agent_skills",
      columns: SKILLS,
      app: {},
      optional: ["createdAt"],
    },
  },
};

/** The keys an agent read returns besides its columns. */
const AGENT_KEYS: readonly string[] = [
  ...Object.values(AGENTS),
  "skills",
  "installed",
  "my_rating",
  "fields",
];

const SLUG = "^[a-z0-9]+(-[a-z0-9]+)*$";

/** What an agent read returns for a column the app's agents table lacks. */
const AGENT_DEFAULTS: Readonly<Record<string, string>> = {
  description: "''",
  instructions: "''",
  tools: "'[]'::jsonb",
  connectors: "'{}'::uuid[]",
  knowledgeScope: "'[]'::jsonb",
  starters: "'[]'::jsonb",
  installCount: "0",
  ratingCount: "0",
  ratingSum: "0",
};

/**
 * The quoted columns of `table`. A column the app's table lacks is empty, so
 * every use of an optional column checks `ctx.has` first.
 */
function presentColumns<T extends Readonly<Record<string, string>>>(
  ctx: BlockSqlContext,
  table: string,
  spec: T,
): Columns<T> {
  // SAFETY: the keys are spec's own keys, each mapped to its quoted name.
  return Object.fromEntries(
    Object.keys(spec).map((key) => [
      key,
      ctx.has(table, key) ? ctx.col(table, key) : "",
    ]),
  ) as Columns<T>;
}

function build(ctx: BlockSqlContext): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const a = presentColumns(ctx, "agents", AGENTS);
  const i = presentColumns(ctx, "installs", INSTALLS);
  const r = presentColumns(ctx, "ratings", RATINGS);
  const s = presentColumns(ctx, "skills", SKILLS);
  const agent = (column: string): boolean => ctx.has("agents", column);

  const line = (present: boolean, definition: string): string =>
    present ? `\n  ${definition},` : "";

  const agents = ctx.table("agents");
  const installs = ctx.table("installs");
  const ratings = ctx.table("ratings");
  const skills = ctx.table("skills");
  const permissions = moduleOperations("agents");
  const read = ctx.permission("read", permissions.read);
  const create = ctx.permission("create", permissions.create);
  const publish = ctx.permission("publish", permissions.publish);
  const moderate = ctx.permission("moderate", permissions.moderate);
  const maxInstructions = ctx.number("maxInstructions", 100_000);

  if (!Number.isInteger(maxInstructions) || maxInstructions < 1) {
    throw new TypeError(
      "blocks.agents.options.maxInstructions must be a positive whole number of characters",
    );
  }

  const extras = ctx.extraColumns("agents", AGENT_KEYS);

  const json = (row: string): string =>
    withExtraFields(
      `jsonb_build_object(${Object.entries(AGENTS)
        .map(
          ([key, name]) =>
            `'${name}', ${agent(key) ? `${row}.${ctx.col("agents", key)}` : (AGENT_DEFAULTS[key] ?? "null")}`,
        )
        .join(", ")})`,
      row,
      extras,
    );

  const setText = (
    key: "slug" | "name" | "description" | "instructions",
  ): string[] =>
    agent(key)
      ? [
          `${a[key]} = coalesce(save_agent.fields ->> '${AGENTS[key]}', x.${a[key]})`,
        ]
      : [];

  const setJson = (key: "tools" | "knowledgeScope" | "starters"): string[] =>
    agent(key)
      ? [
          `${a[key]} = coalesce(save_agent.fields -> '${AGENTS[key]}', x.${a[key]})`,
        ]
      : [];

  const agentUpdate = [
    ...setText("slug"),
    ...setText("name"),
    ...setText("description"),
    ...setText("instructions"),
    ...(agent("model")
      ? [
          `${a.model} = case when save_agent.fields ? 'model' then save_agent.fields ->> 'model' else x.${a.model} end`,
        ]
      : []),
    ...setJson("tools"),
    ...(agent("connectors")
      ? [
          `${a.connectors} = case when save_agent.fields ? 'connector_ids'
      then array(select jsonb_array_elements_text(save_agent.fields -> 'connector_ids')::uuid)
      else x.${a.connectors} end`,
        ]
      : []),
    ...setJson("knowledgeScope"),
    ...setJson("starters"),
    `${a.updatedAt} = now()`,
  ];

  const searched = (["name", "description"] as const)
    .filter((key) => agent(key))
    .map(
      (key) =>
        `x.${a[key]} ilike '%' || replace(replace(list_agents.search, '%', '\\%'), '_', '\\_') || '%'`,
    )
    .join("\n        or ");

  const totals = [
    ...(agent("ratingCount")
      ? [
          `${a.ratingCount} = x.${a.ratingCount} - (case when v_old is null then 0 else 1 end) + (case when rate_agent.rating is null then 0 else 1 end)`,
        ]
      : []),
    ...(agent("ratingSum")
      ? [
          `${a.ratingSum} = x.${a.ratingSum} - coalesce(v_old, 0) + coalesce(rate_agent.rating, 0)`,
        ]
      : []),
  ];

  const ratingTotals =
    totals.length > 0
      ? `
  update ${ctx.table("agents")} x set
    ${totals.join(",\n    ")}
  where x.${a.id} = v_row.${a.id}
  returning * into v_row;`
      : "";

  const installCount = (change: string, indent: string): string =>
    agent("installCount")
      ? `\n${indent}update ${ctx.table("agents")} x set ${a.installCount} = ${change} where x.${a.id} = install_agent.agent_id;`
      : "";

  // Owners see their agents, members the tenant's published ones, every
  // signed-in user the published public ones, moderators all of the tenant's.
  const readable = (row: string): string =>
    `(${row}.${a.owner} = (select auth.uid()) or (${row}.${a.publishedAt} is not null and (${row}.${a.visibility} = 'public' or (${row}.${a.visibility} = 'organization' and ${ctx.scope.check(`${row}.${a.tenant}`, read)}))) or ${ctx.scope.check(`${row}.${a.tenant}`, moderate)})`;

  const canChange = (row: string): string =>
    `(${SERVICE_CALLER} or coalesce(${row}.${a.owner} = auth.uid(), false) or ${ctx.scope.can(`${row}.${a.tenant}`, moderate)})`;

  const notFound = (agent: string): string =>
    raise("agent % not found", "P0002", "AGENT_NOT_FOUND", agent);

  const agentEvent = (type: string, row: string, extra = ""): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${a.tenant}::text, 'agentId', ${row}.${a.id}, 'slug', ${row}.${a.slug}${extra})`,
      subject: `'organizations/' || ${row}.${a.tenant}::text || '/agents/' || ${row}.${a.id}::text`,
      tenant: `${row}.${a.tenant}`,
      audit: {
        category: "ai",
        targetType: "agent",
        recordId: `${row}.${a.id}::text`,
        targetLabel: `${row}.${a.name}`,
      },
    });

  const installEvent = (type: string): string =>
    ctx.record({
      type,
      payload:
        "jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid())",
      subject:
        "'organizations/' || install_agent.tenant::text || '/agents/' || install_agent.agent_id::text",
      tenant: "install_agent.tenant",
      audit: {
        category: "ai",
        targetType: "agent",
        recordId: "install_agent.agent_id::text",
      },
    });

  return `${schemaPreamble(ctx)}
-- Custom assistants: instructions, a model, the tools and connectors they may
-- use and the knowledge they search. An owner keeps an agent private until a
-- member with ${publish} publishes it to the organization or the public store.
create table if not exists ${agents} (
  ${a.id} uuid primary key default gen_random_uuid(),
  ${a.tenant} ${id} not null,
  ${a.owner} uuid references auth.users (id) on delete set null,
  ${a.slug} text not null check (${a.slug} ~ '${SLUG}' and length(${a.slug}) <= 64),
  ${a.name} text not null check (length(${a.name}) between 1 and 200),${line(agent("description"), `${a.description} text not null default '' check (length(${a.description}) <= 2000)`)}
  ${a.instructions} text not null default '' check (length(${a.instructions}) <= ${String(maxInstructions)}),${line(agent("model"), `${a.model} text`)}${line(agent("tools"), `${a.tools} jsonb not null default '[]' check (jsonb_typeof(${a.tools}) = 'array')`)}${line(agent("connectors"), `${a.connectors} uuid[] not null default '{}'`)}${line(agent("knowledgeScope"), `${a.knowledgeScope} jsonb not null default '[]' check (jsonb_typeof(${a.knowledgeScope}) = 'array')`)}${line(agent("starters"), `${a.starters} jsonb not null default '[]' check (jsonb_typeof(${a.starters}) = 'array')`)}
  ${a.visibility} text not null default 'private' check (${a.visibility} in ('private', 'organization', 'public')),
  ${a.publishedAt} timestamptz,${line(agent("installCount"), `${a.installCount} integer not null default 0`)}${line(agent("ratingCount"), `${a.ratingCount} integer not null default 0`)}${line(agent("ratingSum"), `${a.ratingSum} integer not null default 0`)}${line(agent("createdAt"), `${a.createdAt} timestamptz not null default now()`)}
  ${a.updatedAt} timestamptz not null default now(),
  unique (${a.tenant}, ${a.slug})
);
create index if not exists ${ctx.naming.rename("agents_owner_idx")} on ${agents} (${a.owner});${addExtraColumns(agents, extras)}
create index if not exists ${ctx.naming.rename("agents_published_idx")} on ${agents} (${a.visibility}, ${a.publishedAt}) where ${a.publishedAt} is not null;
alter table ${agents} enable row level security;
${revokeTable(agents)}
grant select on ${agents} to authenticated;
grant all on ${agents} to service_role;
${renderPolicy(makePolicy({ name: ctx.naming.rename("agents_read"), table: agents, command: "select", roles: ["authenticated"], using: readable(agents) }), { drop: true, target: agents })}

create table if not exists ${installs} (
  ${i.agent} uuid not null references ${agents} (${a.id}) on delete cascade,
  ${i.user} uuid not null references auth.users (id) on delete cascade,
  ${i.tenant} ${id} not null,${line(ctx.has("installs", "installedAt"), `${i.installedAt} timestamptz not null default now()`)}
  primary key (${i.agent}, ${i.user}, ${i.tenant})
);${ctx.owns("installs") ? "" : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("installs").name}_install_key`)} on ${installs} (${i.agent}, ${i.user}, ${i.tenant});`}
create index if not exists ${ctx.naming.rename("agent_installs_user_idx")} on ${installs} (${i.user}, ${i.tenant});
alter table ${installs} enable row level security;
${revokeTable(installs)}
grant select on ${installs} to authenticated;
grant all on ${installs} to service_role;
${renderPolicy(makePolicy({ table: installs, name: ctx.naming.rename("agent_installs_read"), command: "select", roles: ["authenticated"], using: `${i.user} = (select auth.uid())` }), { drop: true, target: installs })}

create table if not exists ${ratings} (
  ${r.agent} uuid not null references ${agents} (${a.id}) on delete cascade,
  ${r.user} uuid not null references auth.users (id) on delete cascade,
  ${r.rating} smallint not null check (${r.rating} between 1 and 5),${line(ctx.has("ratings", "comment"), `${r.comment} text check (length(${r.comment}) <= 2000)`)}${line(ctx.has("ratings", "createdAt"), `${r.createdAt} timestamptz not null default now()`)}
  primary key (${r.agent}, ${r.user})
);
create index if not exists ${ctx.naming.rename("agent_ratings_user_idx")} on ${ratings} (${r.user});
alter table ${ratings} enable row level security;
${revokeTable(ratings)}
grant select on ${ratings} to authenticated;
grant all on ${ratings} to service_role;
${renderPolicy(makePolicy({ table: ratings, name: ctx.naming.rename("agent_ratings_read"), command: "select", roles: ["authenticated"], using: `exists (select 1 from ${agents} x where x.${a.id} = ${r.agent})` }), { drop: true, target: ratings })}

-- Skills an agent loads from a provider (a reference such as a skill id).
create table if not exists ${skills} (
  ${s.id} uuid primary key default gen_random_uuid(),
  ${s.agent} uuid not null references ${agents} (${a.id}) on delete cascade,
  ${s.provider} text not null check (length(${s.provider}) between 1 and 100),
  ${s.reference} jsonb not null check (jsonb_typeof(${s.reference}) = 'object')${ctx.has("skills", "createdAt") ? `,\n  ${s.createdAt} timestamptz not null default now()` : ""}
);
create index if not exists ${ctx.naming.rename("agent_skills_agent_idx")} on ${skills} (${s.agent});
alter table ${skills} enable row level security;
${revokeTable(skills)}
grant select on ${skills} to authenticated;
grant all on ${skills} to service_role;
${renderPolicy(makePolicy({ table: skills, name: ctx.naming.rename("agent_skills_read"), command: "select", roles: ["authenticated"], using: `exists (select 1 from ${agents} x where x.${a.id} = ${s.agent})` }), { drop: true, target: skills })}

-- Creates an agent (id null, needs ${create}) or changes one its owner or a
-- moderator may change. fields holds the columns to set; visibility and
-- published_at change through publish_agent only.
create or replace function ${fn("save_agent")}(tenant ${id}, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${agents}%rowtype;
begin
  if jsonb_typeof(save_agent.fields) is distinct from 'object' then
    ${raise("fields must be an object", "22023", "AGENT_INVALID")}
  end if;
  if save_agent.id is null then
    if auth.uid() is null or not ${ctx.scope.can("save_agent.tenant", create)} then
      ${raise("you may not create agents here", "42501", "AGENT_FORBIDDEN")}
    end if;
    if save_agent.fields ->> 'slug' is null or save_agent.fields ->> 'name' is null then
      ${raise("a new agent needs a slug and a name", "22023", "AGENT_INVALID")}
    end if;
    insert into ${agents} (${a.tenant}, ${a.owner}, ${a.slug}, ${a.name})
    values (save_agent.tenant, auth.uid(), save_agent.fields ->> 'slug', save_agent.fields ->> 'name')
    returning * into v_row;
  else
    select * into v_row from ${agents} x where x.${a.id} = save_agent.id and x.${a.tenant} = save_agent.tenant for update;
    if not found or not ${canChange("v_row")} then
      ${notFound("save_agent.id")}
    end if;
  end if;
  update ${agents} x set
    ${agentUpdate.join(",\n    ")}
  where x.${a.id} = v_row.${a.id}
  returning * into v_row;${writeExtraColumns(agents, extras, "save_agent.fields", `x.${a.id} = v_row.${a.id}`, "v_row")}
  ${agentEvent("agent.saved", "v_row")}
  return ${json("v_row")};
exception
  when unique_violation then
    ${raise("an agent with slug % exists", "23505", "AGENT_SLUG_TAKEN", "save_agent.fields ->> 'slug'")}
end;
$$;
${userGrant(`${fn("save_agent")}(${id}, uuid, jsonb)`)}

-- Publishes an agent to the organization or the public store, or makes it
-- private again. The owner needs ${publish}; a moderator may always unpublish.
create or replace function ${fn("publish_agent")}(id uuid, visibility text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${agents}%rowtype;
begin
  if publish_agent.visibility is null or publish_agent.visibility not in ('private', 'organization', 'public') then
    ${raise("visibility is private, organization or public", "22023", "AGENT_INVALID")}
  end if;
  select * into v_row from ${agents} x where x.${a.id} = publish_agent.id for update;
  if not found or not ${canChange("v_row")} then
    ${notFound("publish_agent.id")}
  end if;
  if publish_agent.visibility <> 'private' and not (${SERVICE_CALLER} or ${ctx.scope.can(`v_row.${a.tenant}`, moderate)}
    or (coalesce(v_row.${a.owner} = auth.uid(), false) and ${ctx.scope.can(`v_row.${a.tenant}`, publish)})) then
    ${raise("you may not publish agents here", "42501", "AGENT_FORBIDDEN")}
  end if;
  update ${agents} x set
    ${a.visibility} = ${ctx.cast("agents", "visibility", "publish_agent.visibility")},
    ${a.publishedAt} = case when publish_agent.visibility = 'private' then null else coalesce(x.${a.publishedAt}, now()) end,
    ${a.updatedAt} = now()
  where x.${a.id} = v_row.${a.id}
  returning * into v_row;
  ${agentEvent("agent.published", "v_row", ", 'visibility', publish_agent.visibility")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("publish_agent")}(uuid, text)`)}

create or replace function ${fn("delete_agent")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${agents}%rowtype;
begin
  select * into v_row from ${agents} x where x.${a.id} = delete_agent.id;
  if not found or not ${canChange("v_row")} then
    return false;
  end if;
  delete from ${agents} x where x.${a.id} = v_row.${a.id};
  ${agentEvent("agent.deleted", "v_row")}
  return true;
end;
$$;
${userGrant(`${fn("delete_agent")}(uuid)`)}

-- An agent by id or by slug in a tenant, with its skills, when the caller may read it.
create or replace function ${fn("get_agent")}(id uuid default null, tenant ${id} default null, slug text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row ${agents}%rowtype;
begin
  select * into v_row from ${agents} x
  where (get_agent.id is not null and x.${a.id} = get_agent.id)
    or (get_agent.id is null and x.${a.tenant} = get_agent.tenant and x.${a.slug} = get_agent.slug);
  if not found then
    return null;
  end if;
  return ${json("v_row")} || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k.${s.id}, 'provider', k.${s.provider}, 'reference', k.${s.reference}) order by k.${ctx.has("skills", "createdAt") ? s.createdAt : s.id}) from ${skills} k where k.${s.agent} = v_row.${a.id}), '[]'),
    'installed', exists (select 1 from ${installs} n where n.${i.agent} = v_row.${a.id} and n.${i.user} = auth.uid()),
    'my_rating', (select g.${r.rating} from ${ratings} g where g.${r.agent} = v_row.${a.id} and g.${r.user} = auth.uid())
  );
end;
$$;
${userGrant(`${fn("get_agent")}(uuid, ${id}, text)`)}

-- Agents the caller may read: 'mine', 'installed' in the tenant, or the
-- 'store' (published to the tenant or public), newest first.
create or replace function ${fn("list_agents")}(tenant ${id}, filter text default 'store', search text default null, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(y.row order by y.at desc), '[]')
  from (
    select ${json("x")} || jsonb_build_object('installed', exists (select 1 from ${installs} n where n.${i.agent} = x.${a.id} and n.${i.user} = auth.uid() and n.${i.tenant} = list_agents.tenant)) as row,
      coalesce(x.${a.publishedAt}, x.${a.updatedAt}) as at
    from ${agents} x
    where case list_agents.filter
        when 'mine' then x.${a.owner} = auth.uid() and x.${a.tenant} = list_agents.tenant
        when 'installed' then exists (select 1 from ${installs} n where n.${i.agent} = x.${a.id} and n.${i.user} = auth.uid() and n.${i.tenant} = list_agents.tenant)
        else x.${a.publishedAt} is not null and (x.${a.visibility} = 'public' or x.${a.tenant} = list_agents.tenant)
      end
      and (list_agents.search is null or ${searched})
    order by coalesce(x.${a.publishedAt}, x.${a.updatedAt}) desc
    limit least(greatest(list_agents.max_rows, 1), 200)
  ) y
$$;
${userGrant(`${fn("list_agents")}(${id}, text, text, integer)`)}

-- Adds a readable agent to the caller's list in a tenant they belong to, or removes it.
create or replace function ${fn("install_agent")}(tenant ${id}, agent_id uuid, installed boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if auth.uid() is null or not ${ctx.scope.can("install_agent.tenant", read)} then
    ${raise("you may not use agents here", "42501", "AGENT_FORBIDDEN")}
  end if;
  if not install_agent.installed then
    delete from ${installs} n where n.${i.agent} = install_agent.agent_id and n.${i.user} = auth.uid() and n.${i.tenant} = install_agent.tenant;
    get diagnostics v_count = row_count;${installCount(`greatest(x.${a.installCount} - v_count, 0)`, "    ")}
    if v_count > 0 then
      ${installEvent("agent.uninstalled")}
    end if;
    return v_count > 0;
  end if;
  if not exists (select 1 from ${agents} x where x.${a.id} = install_agent.agent_id and ${readable("x")}) then
    ${notFound("install_agent.agent_id")}
  end if;
  insert into ${installs} (${i.agent}, ${i.user}, ${i.tenant}) values (install_agent.agent_id, auth.uid(), install_agent.tenant)
  on conflict do nothing;
  get diagnostics v_count = row_count;${installCount(`x.${a.installCount} + v_count`, "  ")}
  if v_count > 0 then
    ${installEvent("agent.installed")}
  end if;
  return v_count > 0;
end;
$$;
${userGrant(`${fn("install_agent")}(${id}, uuid, boolean)`)}

-- Rates a readable agent 1 to 5, replacing the caller's rating; null removes it.
create or replace function ${fn("rate_agent")}(agent_id uuid, rating integer, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old integer;
  v_row ${agents}%rowtype;
begin
  if auth.uid() is null then
    ${raise("sign in to rate agents", "42501", "AGENT_FORBIDDEN")}
  end if;
  select * into v_row from ${agents} x where x.${a.id} = rate_agent.agent_id and ${readable("x")} for update;
  if not found then
    ${notFound("rate_agent.agent_id")}
  end if;
  if rate_agent.rating is not null and rate_agent.rating not between 1 and 5 then
    ${raise("a rating is 1 to 5", "22023", "AGENT_INVALID")}
  end if;
  delete from ${ratings} g where g.${r.agent} = v_row.${a.id} and g.${r.user} = auth.uid()
  returning g.${r.rating} into v_old;
  if rate_agent.rating is not null then
    insert into ${ratings} (${r.agent}, ${r.user}, ${r.rating}${ctx.has("ratings", "comment") ? `, ${r.comment}` : ""})
    values (v_row.${a.id}, auth.uid(), rate_agent.rating${ctx.has("ratings", "comment") ? ", rate_agent.comment" : ""});
  end if;${ratingTotals}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("rate_agent")}(uuid, integer, text)`)}

-- Replaces an agent's skills with a list of {provider, reference}.
create or replace function ${fn("set_agent_skills")}(agent_id uuid, skills jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${agents}%rowtype;
  v_items jsonb := case when jsonb_typeof(set_agent_skills.skills) = 'object' then set_agent_skills.skills -> 'items' else set_agent_skills.skills end;
  v_count integer;
begin
  select * into v_row from ${agents} x where x.${a.id} = set_agent_skills.agent_id for update;
  if not found or not ${canChange("v_row")} then
    ${notFound("set_agent_skills.agent_id")}
  end if;
  if jsonb_typeof(v_items) is distinct from 'array' then
    ${raise("skills must be a list", "22023", "AGENT_INVALID")}
  end if;
  delete from ${skills} k where k.${s.agent} = v_row.${a.id};
  insert into ${skills} (${s.agent}, ${s.provider}, ${s.reference})
  select v_row.${a.id}, e ->> 'provider', e -> 'reference' from jsonb_array_elements(v_items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${userGrant(`${fn("set_agent_skills")}(uuid, jsonb)`)}`;
}

export const AGENTS_MODULE: BlockSqlDefinition = {
  name: "agents",
  scopes: ["tenant"],
  title: "Agents",
  description:
    "Custom assistants with instructions, a model, tools, connectors, knowledge scopes and starters; private until published to the organization or the public store, with installs, ratings and provider skills.",
  requires: ["memberships", "permissions"],
  target: "schema",
  version: 1,
  names: NAMES,
  build,
};
