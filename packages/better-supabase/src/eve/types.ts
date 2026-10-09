/**
 * eve's `SessionAuthContext`, typed structurally so this entry never imports
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
