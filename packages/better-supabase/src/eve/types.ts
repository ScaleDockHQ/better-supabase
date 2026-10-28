/**
 * Eve's `SessionAuthContext`, typed structurally so this entry never imports
 * eve. `attributes` carries `tenantId`, `roles` and `isAnonymous`.
 */
export interface EveSessionAuth {
  readonly authenticator: string;
  readonly principalType: string;
  readonly principalId: string;
  readonly issuer?: string;
  readonly subject?: string;
  readonly attributes: Readonly<Record<string, string | readonly string[]>>;
}

/** The session part of the context eve passes to hooks, memory and connections. */
export interface EveSessionContext {
  readonly session: {
    readonly id: string;
    readonly auth: {
      readonly current: EveSessionAuth | null;
      readonly initiator?: EveSessionAuth | null;
    };
  };
}

/** The part of eve's `ToolContext` the tools here read. */
export interface EveToolContext extends EveSessionContext {
  readonly callId: string;
  readonly toolName: string;
}

/**
 * Eve's request-time `ApprovalStatus`. `true` means `"user-approval"` and
 * `false` means `"not-applicable"`, as in eve.
 */
export type EveApprovalStatus =
  | undefined
  | boolean
  | "not-applicable"
  | "approved"
  | "denied"
  | "user-approval"
  | { readonly type: "approved"; readonly reason?: string }
  | { readonly type: "denied"; readonly reason?: string };

/** The part of eve's `ApprovalContext` the policies here read. */
export interface EveApprovalContext extends EveSessionContext {
  readonly callId: string;
  readonly toolName: string;
  readonly toolInput?: unknown;
}

/** Eve's `ApprovalPolicy`. */
export type EveApprovalPolicy = (
  ctx: EveApprovalContext,
) => EveApprovalStatus | Promise<EveApprovalStatus>;

/** Eve's `ApprovalResponseContext`: who asked for the call and who answered. */
export interface EveApprovalResponseContext {
  readonly request: {
    readonly callId: string;
    readonly requestId: string;
    readonly principal: EveSessionAuth | null;
    readonly toolName: string;
    readonly toolInput?: unknown;
  };
  readonly response: {
    readonly decision: "approve" | "cancel";
    readonly principal: EveSessionAuth;
  };
  readonly session: { readonly id: string };
}

/** Eve's `ApprovalResponseDecision`. */
export type EveApprovalResponseDecision =
  | { readonly status: "allowed" }
  | { readonly status: "rejected"; readonly reason: string };

/** Eve's `ToolApprovalConfiguration`: the object form of a tool's `approval`. */
export interface EveApprovalConfiguration {
  readonly request: EveApprovalPolicy;
  readonly response?: (
    ctx: EveApprovalResponseContext,
  ) => EveApprovalResponseDecision | Promise<EveApprovalResponseDecision>;
  readonly prompt?: (ctx: {
    readonly callId: string;
    readonly input: unknown;
    readonly toolName: string;
  }) => string;
}

/** A tool's `approval`: a policy function or its object form. */
export type EveToolApproval = EveApprovalPolicy | EveApprovalConfiguration;
