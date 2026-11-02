import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { DenyTopic, PiiKind } from "./heuristics.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { consoleLogger } from "../../core/logger.ts";
import { ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  instantOf,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  sha256Hex,
  textOf,
} from "../shared.ts";
import {
  detectInjection,
  matchTopics,
  PII_KINDS,
  scanPii,
} from "./heuristics.ts";

export type GuardrailStage = "input" | "output";

export type GuardrailDecision = "allow" | "redact" | "block";

/** What a check does when a heuristic matches. `flag` only logs the reason. */
export type GuardrailAction = "block" | "flag";

export type PiiAction = "block" | "redact" | "flag";

/** The config of one policy: every key is optional and off when absent. */
export interface GuardrailPolicyConfig {
  /** Prompt-injection heuristics (OWASP LLM01), checked on `input` text. */
  readonly injection?: { readonly action: GuardrailAction };
  /** PII detection; `redact` replaces matches and lets the text through. */
  readonly pii?: {
    readonly action: PiiAction;
    /** Default: every kind. */
    readonly kinds?: readonly PiiKind[];
  };
  /** Topics the agent never discusses. A string is its own term. */
  readonly denyTopics?: readonly (DenyTopic | string)[];
  /** The deepest chain of tool calls a run may reach. */
  readonly maxToolDepth?: number;
}

export interface GuardrailPolicy {
  readonly id: string;
  readonly organizationId: string | undefined;
  /** The agent the policy applies to, or `*` for every agent. */
  readonly agent: string;
  readonly stage: GuardrailStage;
  readonly config: GuardrailPolicyConfig;
  readonly enabled: boolean;
  readonly updatedAt: Temporal.Instant;
}

/** One reason a check flagged, redacted or blocked content. */
export interface GuardrailReason {
  /** `injection`, `pii`, `topic` or `tool_depth`. */
  readonly code: "injection" | "pii" | "topic" | "tool_depth";
  /** The rule id, PII kind or topic name. */
  readonly detail: string;
  /** Whether this reason alone blocks. */
  readonly blocking: boolean;
}

export interface GuardrailLogEntry {
  readonly id: string;
  readonly organizationId: string | undefined;
  readonly agent: string;
  readonly stage: GuardrailStage;
  readonly decision: GuardrailDecision;
  readonly reasons: readonly GuardrailReason[];
  readonly chatId: string | undefined;
  readonly contentHash: string | undefined;
  readonly createdAt: Temporal.Instant;
}

/** The outcome of a check. */
export interface GuardrailVerdict {
  readonly decision: GuardrailDecision;
  /** The text to pass on: redacted for `redact`, unchanged otherwise. */
  readonly text: string;
  readonly reasons: readonly GuardrailReason[];
  /** The decision log row; `undefined` when no policy applied or logging failed. */
  readonly logged: GuardrailLogEntry | undefined;
}

export interface GuardrailCheckInput {
  /** The agent whose policy applies. */
  readonly agent: string;
  readonly stage: GuardrailStage;
  readonly text: string;
  readonly organizationId?: string;
  readonly chatId?: string;
  /** The number of tool calls in the chain so far. */
  readonly toolDepth?: number;
  /** A policy to use instead of the stored one. */
  readonly policy?: GuardrailPolicyConfig;
}

export interface AiGuardrailsOptions extends BlockTemporalOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<AiGuardrails>>;
  /**
   * Receives log failures and the errors `after` hooks throw. Default:
   * `console`.
   */
  readonly logger?: Logger;
  /** Calls as the service role: the log records which content was blocked. */
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface AiGuardrails {
  readonly policies: {
    /**
     * Saves the policy for an agent (or `*`) at a stage, for a tenant or the
     * system.
     */
    upsert(
      input: {
        agent: string;
        stage: GuardrailStage;
        config: GuardrailPolicyConfig;
      } & { readonly organizationId?: string; readonly enabled?: boolean },
    ): AsyncResult<GuardrailPolicy>;
    /**
     * The enabled policy that applies: the tenant's for the agent, the tenant's
     * for `*`, then the system's. `undefined` when none applies.
     */
    get(
      input: { agent: string; stage: GuardrailStage } & {
        readonly organizationId?: string;
      },
    ): AsyncResult<GuardrailPolicy | undefined>;
  };
  readonly decisions: {
    /** The decision log, newest first. */
    list(options?: {
      readonly agent?: string;
      readonly decision?: GuardrailDecision;
      readonly organizationId?: string;
      readonly limit?: number;
    }): AsyncResult<readonly GuardrailLogEntry[]>;
    /** Deletes the decisions older than the module's retention; the count. */
    purge(): AsyncResult<number>;
  };
  /**
   * Checks text against the policy that applies and logs the decision. It only
   * reads the text: it never changes a repository `Result`. Without a policy
   * the text is allowed and nothing is logged.
   */
  check(input: GuardrailCheckInput): AsyncResult<GuardrailVerdict>;
}

const isAction = (value: unknown): value is GuardrailAction =>
  value === "block" || value === "flag";

function configOf(value: unknown): GuardrailPolicyConfig {
  if (!isRecord(value)) {
    return {};
  }

  const injection = value["injection"];
  const pii = value["pii"];
  const topics = value["denyTopics"];
  const depth = value["maxToolDepth"];

  const listed: readonly unknown[] =
    isRecord(pii) && Array.isArray(pii["kinds"]) ? pii["kinds"] : [];

  const kinds =
    listed.length > 0
      ? PII_KINDS.filter((kind) => listed.includes(kind))
      : undefined;

  return {
    ...(isRecord(injection) && isAction(injection["action"])
      ? { injection: { action: injection["action"] } }
      : {}),
    ...(isRecord(pii) &&
    (pii["action"] === "block" ||
      pii["action"] === "redact" ||
      pii["action"] === "flag")
      ? { pii: { action: pii["action"], ...(kinds ? { kinds } : {}) } }
      : {}),
    ...(Array.isArray(topics)
      ? {
          denyTopics: topics.flatMap((entry): (DenyTopic | string)[] => {
            if (typeof entry === "string") {
              return [entry];
            }

            return isRecord(entry) &&
              typeof entry["topic"] === "string" &&
              Array.isArray(entry["terms"])
              ? [
                  {
                    topic: entry["topic"],
                    terms: entry["terms"].filter(
                      (term): term is string => typeof term === "string",
                    ),
                  },
                ]
              : [];
          }),
        }
      : {}),
    ...(typeof depth === "number" ? { maxToolDepth: depth } : {}),
  };
}

function policyOf(value: unknown): GuardrailPolicy {
  const row = recordOf(value, "guardrail_policies");
  const stage = row["stage"] === "output" ? "output" : "input";

  return {
    id: textOf(row["id"]),
    organizationId: optionalText(row["organization_id"]),
    agent: textOf(row["agent"]),
    stage,
    config: configOf(row["config"]),
    enabled: row["enabled"] !== false,
    updatedAt: instantOf(row["updated_at"]),
  };
}

function reasonsOf(value: unknown): GuardrailReason[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((entry): GuardrailReason[] => {
    if (!isRecord(entry)) {
      return [];
    }

    const code = entry["code"];

    return code === "injection" ||
      code === "pii" ||
      code === "topic" ||
      code === "tool_depth"
      ? [
          {
            code,
            detail: textOf(entry["detail"] ?? ""),
            blocking: entry["blocking"] === true,
          },
        ]
      : [];
  });
}

function entryOf(value: unknown): GuardrailLogEntry {
  const row = recordOf(value, "guardrail_decisions");
  const decision = row["decision"];

  return {
    id: textOf(row["id"]),
    organizationId: optionalText(row["organization_id"]),
    agent: textOf(row["agent"]),
    stage: row["stage"] === "output" ? "output" : "input",
    decision:
      decision === "block" || decision === "redact" ? decision : "allow",
    reasons: reasonsOf(row["reasons"]),
    chatId: optionalText(row["chat_id"]),
    contentHash: optionalText(row["content_hash"]),
    createdAt: instantOf(row["created_at"]),
  };
}

/**
 * Runs a policy over text without any I/O: the pure part of `check`. Injection
 * heuristics only run on `input` text.
 */
export function evaluateGuardrails(
  config: GuardrailPolicyConfig,
  stage: GuardrailStage,
  text: string,
  toolDepth = 0,
): Pick<GuardrailVerdict, "decision" | "reasons" | "text"> {
  const reasons: GuardrailReason[] = [];
  let current = text;
  let redacted = false;

  if (config.injection && stage === "input") {
    for (const rule of detectInjection(text)) {
      reasons.push({
        code: "injection",
        detail: rule,
        blocking: config.injection.action === "block",
      });
    }
  }

  if (config.pii) {
    const scan = scanPii(text, config.pii.kinds);
    const kinds = Object.keys(scan.found);

    for (const kind of kinds) {
      reasons.push({
        code: "pii",
        detail: kind,
        blocking: config.pii.action === "block",
      });
    }

    if (config.pii.action === "redact" && kinds.length > 0) {
      current = scan.redacted;
      redacted = true;
    }
  }

  if (config.denyTopics) {
    for (const topic of matchTopics(text, config.denyTopics)) {
      reasons.push({ code: "topic", detail: topic, blocking: true });
    }
  }

  if (config.maxToolDepth !== undefined && toolDepth > config.maxToolDepth) {
    reasons.push({
      code: "tool_depth",
      detail: `${toolDepth} > ${config.maxToolDepth}`,
      blocking: true,
    });
  }

  const blocking = reasons.some((reason) => reason.blocking);

  return {
    decision: blocking ? "block" : redacted ? "redact" : "allow",
    reasons,
    text: blocking ? text : current,
  };
}

/**
 * Per-agent input and output policies in Postgres and the checks that apply
 * them. The log keeps a hash of the content, never the content.
 */
export function createAiGuardrails(options: AiGuardrailsOptions): AiGuardrails {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const logger = options.logger ?? consoleLogger;

  const client: AiGuardrails = {
    policies: {
      upsert: ({ agent, stage, config, ...setOptions }) =>
        call(
          "set_guardrail_policy",
          {
            agent,
            stage,
            config,
            tenant: setOptions.organizationId,
            enabled: setOptions.enabled ?? true,
          },
          policyOf,
        ),
      get: ({ agent, stage, ...getOptions }) =>
        call(
          "get_guardrail_policy",
          { agent, stage, tenant: getOptions.organizationId },
          (value) =>
            value === null || value === undefined ? undefined : policyOf(value),
        ),
    },
    decisions: {
      list: (listOptions = {}) =>
        call(
          "list_guardrail_decisions",
          {
            agent: listOptions.agent,
            decision: listOptions.decision,
            tenant: listOptions.organizationId,
            max_rows: listOptions.limit,
          },
          (value) => recordsOf(value, "list_guardrail_decisions").map(entryOf),
        ),
      purge: () => call("purge_guardrail_decisions", {}, Number),
    },
    check: (input) =>
      client.policies

        .get({
          agent: input.agent,
          stage: input.stage,
          ...(input.organizationId
            ? { organizationId: input.organizationId }
            : {}),
        })
        .andThen(async (stored) => {
          const config = input.policy ?? stored?.config;

          if (config === undefined) {
            return ok({
              decision: "allow",
              text: input.text,
              reasons: [],
              logged: undefined,
            } satisfies GuardrailVerdict);
          }

          const verdict = evaluateGuardrails(
            config,
            input.stage,
            input.text,
            input.toolDepth,
          );

          const logged = await call(
            "record_guardrail_decision",
            {
              agent: input.agent,
              stage: input.stage,
              decision: verdict.decision,
              reasons: verdict.reasons,
              tenant: input.organizationId,
              chat: input.chatId,
              content_hash: await sha256Hex(input.text),
            },
            entryOf,
          );

          if (!logged.ok) {
            logger.warn("ai-guardrails: could not log a decision", {
              error: logged.error,
            });
          }

          return ok({
            ...verdict,
            logged: logged.ok ? logged.data : undefined,
          } satisfies GuardrailVerdict);
        }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "ai-guardrails",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

/** What `guardrailMiddleware` returns to the caller. */
export interface GuardedResult {
  /** The text to show: the model's answer, redacted, or `refusal`. */
  readonly text: string;
  /** `blocked` at which stage, or `undefined` when the answer went through. */
  readonly blockedAt: GuardrailStage | undefined;
  readonly input: GuardrailVerdict;
  readonly output: GuardrailVerdict | undefined;
}

export interface GuardrailMiddlewareOptions {
  readonly agent: string;
  readonly organizationId?: string;
  readonly chatId?: string;
  /** What the caller sees when a stage blocks. Default: a short refusal. */
  readonly refusal?: string;
  /**
   * What to do when a check cannot run (the database is unreachable). Default
   * `false`: the stage blocks, so an outage does not switch the policy off.
   */
  readonly failOpen?: boolean;
}

const DEFAULT_REFUSAL = "This request can't be processed.";

/**
 * Wraps one model step of an ai-chat agent: it checks the input, calls `next`
 * with the (possibly redacted) input, then checks the answer. It reads and
 * rewrites text only; a repository `Result` is never touched.
 */
export function guardrailMiddleware(
  guardrails: Pick<AiGuardrails, "check">,
  options: GuardrailMiddlewareOptions,
): (
  text: string,
  next: (text: string) => Promise<string>,
  context?: { readonly toolDepth?: number },
) => Promise<GuardedResult> {
  const refusal = options.refusal ?? DEFAULT_REFUSAL;

  const run = async (
    stage: GuardrailStage,
    text: string,
    toolDepth: number | undefined,
  ): Promise<GuardrailVerdict> => {
    const checked = await guardrails.check({
      agent: options.agent,
      stage,
      text,
      ...(options.organizationId
        ? { organizationId: options.organizationId }
        : {}),
      ...(options.chatId ? { chatId: options.chatId } : {}),
      ...(toolDepth === undefined ? {} : { toolDepth }),
    });

    if (checked.ok) {
      return checked.data;
    }

    return {
      decision: options.failOpen ? "allow" : "block",
      text,
      reasons: options.failOpen
        ? []
        : [
            {
              code: "injection",
              detail: "guardrail_unavailable",
              blocking: true,
            },
          ],
      logged: undefined,
    };
  };

  return async (text, next, context = {}) => {
    const input = await run("input", text, context.toolDepth);

    if (input.decision === "block") {
      return { text: refusal, blockedAt: "input", input, output: undefined };
    }

    const answer = await next(input.text);
    const output = await run("output", answer, context.toolDepth);

    return output.decision === "block"
      ? { text: refusal, blockedAt: "output", input, output }
      : { text: output.text, blockedAt: undefined, input, output };
  };
}
