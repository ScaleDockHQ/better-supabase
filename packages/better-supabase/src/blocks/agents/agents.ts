import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { KnowledgeScope } from "../knowledge/knowledge.ts";

import { AsyncResult } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  isRecord,
  notFoundError,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  stringsOf,
  textOf,
  toInstant,
  type BlockTemporalOptions,
} from "../shared.ts";

export type AgentVisibility = "private" | "organization" | "public";

/** A knowledge scope an agent searches: its own (`agent`) or another one. */
export interface AgentKnowledgeScope {
  readonly scope: KnowledgeScope;
  readonly id?: string;
}

export interface AgentSkill {
  readonly id: string;
  /** Who serves the skill, such as `vercel` or `local`. */
  readonly provider: string;
  readonly reference: Readonly<Record<string, unknown>>;
}

export interface Agent {
  readonly id: string;
  readonly organizationId: string;
  readonly ownerId: string | undefined;
  readonly slug: string;
  readonly name: string;
  readonly description: string;
  readonly instructions: string;
  /** A model id for the app's provider registry; the app's default when unset. */
  readonly model: string | undefined;
  /** The names of the tools the agent may call. */
  readonly tools: readonly string[];
  readonly connectorIds: readonly string[];
  readonly knowledgeScopes: readonly AgentKnowledgeScope[];
  /** Prompts the chat offers before the first message. */
  readonly starters: readonly string[];
  readonly visibility: AgentVisibility;
  readonly publishedAt: Temporal.Instant | undefined;
  readonly installCount: number;
  readonly ratingCount: number;
  /** The mean rating, or `undefined` before the first one. */
  readonly rating: number | undefined;
  /** Whether the caller installed it; only `get` and `list` set it. */
  readonly installed: boolean;
  /** The caller's rating; only `get` sets it. */
  readonly myRating: number | undefined;
  /** Only `get` loads the skills. */
  readonly skills: readonly AgentSkill[];
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface AgentFields {
  readonly slug?: string;
  readonly name?: string;
  readonly description?: string;
  readonly instructions?: string;
  readonly model?: string | null;
  readonly tools?: readonly string[];
  readonly connectorIds?: readonly string[];
  readonly knowledgeScopes?: readonly AgentKnowledgeScope[];
  readonly starters?: readonly string[];
}

export type NewAgent = AgentFields & {
  readonly slug: string;
  readonly name: string;
};

export type AgentFilter = "store" | "mine" | "installed";

export interface AgentsOptions extends BlockTemporalOptions {
  /** Calls as the user: `rpcTransport(supabase)`. */
  readonly transport: BlockTransport;
  /** The module schema (`sql.modules.agents.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface Agents {
  create(organizationId: string, agent: NewAgent): AsyncResult<Agent>;
  update(
    organizationId: string,
    agentId: string,
    fields: AgentFields,
  ): AsyncResult<Agent>;
  get(agentId: string): AsyncResult<Agent>;
  bySlug(organizationId: string, slug: string): AsyncResult<Agent>;
  /** The store (published to the tenant or public), the caller's own, or the installed ones. */
  list(
    organizationId: string,
    options?: {
      readonly filter?: AgentFilter;
      readonly search?: string;
      readonly limit?: number;
    },
  ): AsyncResult<readonly Agent[]>;
  publish(agentId: string, visibility: AgentVisibility): AsyncResult<Agent>;
  install(
    organizationId: string,
    agentId: string,
    installed?: boolean,
  ): AsyncResult<boolean>;
  /** Rates 1 to 5; `null` removes the caller's rating. */
  rate(
    agentId: string,
    rating: number | null,
    comment?: string,
  ): AsyncResult<Agent>;
  setSkills(
    agentId: string,
    skills: readonly Omit<AgentSkill, "id">[],
  ): AsyncResult<number>;
  remove(agentId: string): AsyncResult<boolean>;
}

const VISIBILITIES: ReadonlySet<string> = new Set([
  "private",
  "organization",
  "public",
]);

const visibilityOf = (value: unknown): AgentVisibility => {
  const text = textOf(value);
  // SAFETY: VISIBILITIES holds exactly the AgentVisibility members.
  return VISIBILITIES.has(text) ? (text as AgentVisibility) : "private";
};

const instant = (value: unknown): Temporal.Instant =>
  value instanceof Date ? toInstant(value) : toInstant(textOf(value));

function scopesOf(value: unknown): readonly AgentKnowledgeScope[] {
  if (!Array.isArray(value)) return [];
  return value.filter(isRecord).map((item) => {
    const id = optionalText(item["id"]);
    // SAFETY: the table only stores scopes the knowledge block wrote.
    const scope = textOf(item["scope"]) as KnowledgeScope;
    return id === undefined ? { scope } : { scope, id };
  });
}

function skillsOf(value: unknown): readonly AgentSkill[] {
  if (!Array.isArray(value)) return [];
  return value.filter(isRecord).map((item) => ({
    id: textOf(item["id"]),
    provider: textOf(item["provider"]),
    reference: isRecord(item["reference"]) ? item["reference"] : {},
  }));
}

function agentOf(value: unknown): Agent {
  const row = recordOf(value, "agents");
  const ratingCount = Number(row["rating_count"] ?? 0);
  const rating = row["my_rating"];
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    ownerId: optionalText(row["owner_id"]),
    slug: textOf(row["slug"]),
    name: textOf(row["name"]),
    description: textOf(row["description"] ?? ""),
    instructions: textOf(row["instructions"] ?? ""),
    model: optionalText(row["model"]),
    tools: stringsOf(row["tools"]),
    connectorIds: stringsOf(row["connector_ids"]),
    knowledgeScopes: scopesOf(row["knowledge_scope"]),
    starters: stringsOf(row["starters"]),
    visibility: visibilityOf(row["visibility"]),
    publishedAt: optionalInstant(row["published_at"]),
    installCount: Number(row["install_count"] ?? 0),
    ratingCount,
    rating:
      ratingCount === 0
        ? undefined
        : Number(row["rating_sum"] ?? 0) / ratingCount,
    installed: row["installed"] === true,
    myRating:
      rating === null || rating === undefined ? undefined : Number(rating),
    skills: skillsOf(row["skills"]),
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

const notFound = (): DbError =>
  notFoundError("No agent you can see has this id", "AGENT_NOT_FOUND");

function fieldsArg(fields: AgentFields): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (fields.slug !== undefined) out["slug"] = fields.slug;
  if (fields.name !== undefined) out["name"] = fields.name;
  if (fields.description !== undefined) out["description"] = fields.description;
  if (fields.instructions !== undefined) {
    out["instructions"] = fields.instructions;
  }
  if (fields.model !== undefined) out["model"] = fields.model;
  if (fields.tools !== undefined) out["tools"] = fields.tools;
  if (fields.connectorIds !== undefined) {
    out["connector_ids"] = fields.connectorIds;
  }
  if (fields.knowledgeScopes !== undefined) {
    out["knowledge_scope"] = fields.knowledgeScopes;
  }
  if (fields.starters !== undefined) out["starters"] = fields.starters;
  return out;
}

/** Custom assistants: build, publish to a store, install and rate. */
export function createAgents(options: AgentsOptions): Agents {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const found = (value: unknown): AsyncResult<Agent> =>
    isRecord(value)
      ? AsyncResult.ok(agentOf(value))
      : AsyncResult.err(notFound());
  const save = (
    organizationId: string,
    agentId: string | undefined,
    fields: AgentFields,
  ): AsyncResult<Agent> =>
    call(
      "save_agent",
      { tenant: organizationId, id: agentId, fields: fieldsArg(fields) },
      agentOf,
    );

  return {
    create: (organizationId, agent) => save(organizationId, undefined, agent),
    update: (organizationId, agentId, fields) =>
      save(organizationId, agentId, fields),
    get: (agentId) =>
      call("get_agent", { id: agentId }, (value) => value).andThen(found),
    bySlug: (organizationId, slug) =>
      call(
        "get_agent",
        { tenant: organizationId, slug },
        (value) => value,
      ).andThen(found),
    list: (organizationId, listOptions = {}) =>
      call(
        "list_agents",
        {
          tenant: organizationId,
          filter: listOptions.filter,
          search: listOptions.search,
          max_rows: listOptions.limit,
        },
        (value) => recordsOf(value, "list_agents").map(agentOf),
      ),
    publish: (agentId, visibility) =>
      call("publish_agent", { id: agentId, visibility }, agentOf),
    install: (organizationId, agentId, installed = true) =>
      call(
        "install_agent",
        { tenant: organizationId, agent_id: agentId, installed },
        (value) => value === true,
      ),
    rate: (agentId, rating, comment) =>
      call("rate_agent", { agent_id: agentId, rating, comment }, agentOf),
    setSkills: (agentId, skills) =>
      call(
        "set_agent_skills",
        { agent_id: agentId, skills: { items: skills } },
        Number,
      ),
    remove: (agentId) =>
      call("delete_agent", { id: agentId }, (value) => value === true),
  };
}
