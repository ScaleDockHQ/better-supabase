import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { KnowledgeScope } from "../knowledge/knowledge.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import {
  allWithFields,
  blockFields,
  extraOf,
  withFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
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
  instantOf,
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
  /** The skill's name, when its files are kept in Storage. */
  readonly name?: string;
  /** The skill's files in Storage: a relative `path` and the Storage `object`. */
  readonly files?: readonly AgentSkillFile[];
  /** A hash of the files' bytes; `syncSkill` uploads again when it changes. */
  readonly contentHash?: string;
  readonly latestVersion?: string;
  /**
   * What each provider returned, keyed by provider, for the hash it was
   * uploaded from.
   */
  readonly providerRefs?: Readonly<Record<string, AgentSkillProviderRef>>;
}

export interface AgentSkillFile {
  readonly path: string;
  /** The Storage object, such as `skills/<id>/SKILL.md`. */
  readonly object: string;
}

export interface AgentSkillProviderRef {
  readonly reference: Readonly<Record<string, unknown>>;
  readonly contentHash: string;
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

export interface AgentsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  /**
   * A Standard Schema for the agent columns the app adds (columns the app's
   * schema files add to the table), keyed by column name. It types and parses
   * them on every read, and validates them on `create` and `update`, which
   * return a `validation` error for a bad value.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Agents<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  /** Calls as the user: `rpcTransport(supabase)`. */
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

/** `F` is the extra fields `options.fields` describes. */
export interface Agents<F extends object = Record<never, never>> {
  /** Keys besides the agent's own are its extra columns. */
  create(input: {
    organizationId: string;
    agent: NewAgent & Partial<F>;
  }): AsyncResult<Agent & F>;
  update(input: {
    organizationId: string;
    agentId: string;
    fields: AgentFields & Partial<F>;
  }): AsyncResult<Agent & F>;
  get(agentId: string): AsyncResult<Agent & F>;
  bySlug(input: {
    organizationId: string;
    slug: string;
  }): AsyncResult<Agent & F>;
  /**
   * The store (published to the tenant or public), the caller's own, or the
   * installed ones.
   */
  list(
    input: { organizationId: string } & {
      readonly filter?: AgentFilter;
      readonly search?: string;
      readonly limit?: number;
    },
  ): AsyncResult<readonly (Agent & F)[]>;
  publish(input: {
    agentId: string;
    visibility: AgentVisibility;
  }): AsyncResult<Agent & F>;
  install(input: {
    organizationId: string;
    agentId: string;
    installed?: boolean | undefined;
  }): AsyncResult<boolean>;
  /** Rates 1 to 5; `null` removes the caller's rating. */
  rate(input: {
    agentId: string;
    rating: number | null;
    comment?: string | undefined;
  }): AsyncResult<Agent & F>;
  setSkills(input: {
    agentId: string;
    skills: readonly Omit<AgentSkill, "id">[];
  }): AsyncResult<number>;
  /**
   * Stores what a provider returned for a skill's current content. Needs the
   * service role. `syncSkill` calls it.
   */
  recordSkillSync(input: {
    skillId: string;
    provider: string;
    reference: Readonly<Record<string, unknown>>;
    contentHash: string;
  }): AsyncResult<Readonly<Record<string, AgentSkillProviderRef>>>;
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

function scopesOf(value: unknown): readonly AgentKnowledgeScope[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter(isRecord).map((item) => {
    const id = optionalText(item["id"]);
    // SAFETY: the table only stores scopes the knowledge block wrote.
    const scope = textOf(item["scope"]) as KnowledgeScope;

    return id === undefined ? { scope } : { scope, id };
  });
}

function skillFilesOf(value: readonly unknown[]): readonly AgentSkillFile[] {
  return value
    .filter(isRecord)
    .map((file) => ({
      path: textOf(file["path"]),
      object: textOf(file["object"]),
    }));
}

function providerRefsOf(
  value: unknown,
): Readonly<Record<string, AgentSkillProviderRef>> {
  if (!isRecord(value)) {
    return {};
  }

  const refs: Record<string, AgentSkillProviderRef> = {};

  for (const [provider, entry] of Object.entries(value)) {
    if (isRecord(entry)) {
      refs[provider] = {
        reference: isRecord(entry["reference"]) ? entry["reference"] : {},
        contentHash: textOf(entry["content_hash"]),
      };
    }
  }

  return refs;
}

function skillsOf(value: unknown): readonly AgentSkill[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter(isRecord).map((item) => {
    const name = item["name"];
    const hash = item["content_hash"];
    const version = item["latest_version"];

    return {
      id: textOf(item["id"]),
      provider: textOf(item["provider"]),
      reference: isRecord(item["reference"]) ? item["reference"] : {},
      ...(typeof name === "string" ? { name } : {}),
      ...(Array.isArray(item["files"])
        ? { files: skillFilesOf(item["files"]) }
        : {}),
      ...(typeof hash === "string" ? { contentHash: hash } : {}),
      ...(typeof version === "string" ? { latestVersion: version } : {}),
      providerRefs: providerRefsOf(item["provider_refs"]),
    };
  });
}

function agentOf(value: unknown): Agent {
  const row = recordOf(value, "agents");
  const ratingCount = Number(row["rating_count"] ?? 0);
  const rating = row["my_rating"];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
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
    createdAt: instantOf(row["created_at"]),
    updatedAt: instantOf(row["updated_at"]),
  };
}

const notFound = (): DbError =>
  notFoundError("No agent you can see has this id", "AGENT_NOT_FOUND");

const AGENT_FIELDS: ReadonlySet<string> = new Set([
  "slug",
  "name",
  "description",
  "instructions",
  "model",
  "tools",
  "connectorIds",
  "knowledgeScopes",
  "starters",
]);

function fieldsArg(fields: AgentFields): Record<string, unknown> {
  const out: Record<string, unknown> = {};

  if (fields.slug !== undefined) {
    out["slug"] = fields.slug;
  }

  if (fields.name !== undefined) {
    out["name"] = fields.name;
  }

  if (fields.description !== undefined) {
    out["description"] = fields.description;
  }

  if (fields.instructions !== undefined) {
    out["instructions"] = fields.instructions;
  }

  if (fields.model !== undefined) {
    out["model"] = fields.model;
  }

  if (fields.tools !== undefined) {
    out["tools"] = fields.tools;
  }

  if (fields.connectorIds !== undefined) {
    out["connector_ids"] = fields.connectorIds;
  }

  if (fields.knowledgeScopes !== undefined) {
    out["knowledge_scope"] = fields.knowledgeScopes;
  }

  if (fields.starters !== undefined) {
    out["starters"] = fields.starters;
  }

  return out;
}

/** Custom assistants: build, publish to a store, install and rate. */
export function createAgents<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: AgentsOptions<S>): Agents<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "agent fields");

  const typed = (value: unknown): AsyncResult<Agent & F> =>
    AsyncResult.from(() => withFields(fields, value, agentOf(value)));

  const one = (
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ): AsyncResult<Agent & F> => call(fn, args, (value) => value).andThen(typed);

  const found = (value: unknown): AsyncResult<Agent & F> =>
    isRecord(value) ? typed(value) : AsyncResult.err(notFound());

  const save = (
    organizationId: string,
    agentId: string | undefined,
    agent: AgentFields,
  ): AsyncResult<Agent & F> =>
    AsyncResult.from(() => fields.write(extraOf(agent, AGENT_FIELDS))).andThen(
      (extra) =>
        one("save_agent", {
          tenant: organizationId,
          id: agentId,
          fields: { ...extra, ...fieldsArg(agent) },
        }),
    );

  const client: Agents<F> = {
    create: ({ organizationId, agent }) =>
      save(organizationId, undefined, agent),
    update: ({ organizationId, agentId, fields }) =>
      save(organizationId, agentId, fields),
    get: (agentId) =>
      call("get_agent", { id: agentId }, (value) => value).andThen(found),
    bySlug: ({ organizationId, slug }) =>
      call(
        "get_agent",
        { tenant: organizationId, slug },
        (value) => value,
      ).andThen(found),
    list: ({ organizationId, ...listOptions }) =>
      call(
        "list_agents",
        {
          tenant: organizationId,
          filter: listOptions.filter,
          search: listOptions.search,
          max_rows: listOptions.limit,
        },
        (value) =>
          recordsOf(value, "list_agents").map(
            (raw) => [raw, agentOf(raw)] as const,
          ),
      ).andThen((rows) => allWithFields(fields, rows)),
    publish: ({ agentId, visibility }) =>
      one("publish_agent", { id: agentId, visibility }),
    install: ({ organizationId, agentId, installed = true }) =>
      call(
        "install_agent",
        { tenant: organizationId, agent_id: agentId, installed },
        (value) => value === true,
      ),
    rate: ({ agentId, rating, comment }) =>
      one("rate_agent", { agent_id: agentId, rating, comment }),
    setSkills: ({ agentId, skills }) =>
      call(
        "set_agent_skills",
        {
          agent_id: agentId,
          skills: {
            items: skills.map((skill) => ({
              provider: skill.provider,
              reference: skill.reference,
              name: skill.name,
              files: skill.files,
              content_hash: skill.contentHash,
              latest_version: skill.latestVersion,
              provider_refs: skill.providerRefs,
            })),
          },
        },
        Number,
      ),
    recordSkillSync: ({ skillId, provider, reference, contentHash }) =>
      call(
        "record_skill_sync",
        { skill_id: skillId, provider, reference, content_hash: contentHash },
        providerRefsOf,
      ),
    remove: (agentId) =>
      call("delete_agent", { id: agentId }, (value) => value === true),
  };

  return withBlockHooks(client, options.hooks, {
    block: "agents",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
