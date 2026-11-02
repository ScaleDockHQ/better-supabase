import type { DamUsageRight } from "./dam.ts";

export const ODRL_CONTEXT = "http://www.w3.org/ns/odrl.jsonld";

export interface OdrlOptions {
  /** The policy's IRI. Default `urn:uuid:` plus the first right's id. */
  readonly uid?: string;
  /** The IRI of the party that grants the rights, such as the organization. */
  readonly assigner: string;
  /** The IRI of the asset, such as its public URL. */
  readonly target: string;
  /** Maps a right's `licensee` to an assignee IRI. Default: the text itself. */
  readonly assignee?: (licensee: string) => string;
  /**
   * The ODRL action the rights permit. Default `use`; a DAM may grant
   * `distribute` or `reproduce` instead.
   */
  readonly action?: string;
}

export interface OdrlConstraint {
  readonly leftOperand: string;
  readonly operator: string;
  readonly rightOperand: unknown;
}

export interface OdrlPermission {
  readonly target: string;
  readonly assigner: string;
  readonly assignee: string;
  readonly action: string;
  readonly constraint: readonly OdrlConstraint[];
}

/** An ODRL 2.2 Set policy as JSON-LD. */
export interface OdrlPolicy {
  readonly "@context": string;
  readonly type: "Set";
  readonly uid: string;
  readonly profile?: string;
  readonly permission: readonly OdrlPermission[];
}

function dateOperand(date: Temporal.PlainDate): {
  "@value": string;
  "@type": string;
} {
  return { "@value": date.toString(), "@type": "xsd:date" };
}

/**
 * Exports a file's usage rights as an ODRL 2.2 Set: one permission per active
 * right, with the territory as a `spatial` constraint, the channel as a
 * `purpose` constraint and the dates as `dateTime` constraints. Revoked and
 * expired rights are left out, as `check` treats them as no right. ODRL is the
 * export format only: the DAM's table stays the source of truth, and an ODRL
 * policy read back is not imported.
 */
export function damUsageRightsToOdrl(
  rights: readonly DamUsageRight[],
  options: OdrlOptions,
): OdrlPolicy {
  const active = rights.filter(
    (right) => right.status === "active" && right.revokedAt === undefined,
  );

  return {
    "@context": ODRL_CONTEXT,
    type: "Set",
    uid: options.uid ?? `urn:uuid:${active[0]?.id ?? crypto.randomUUID()}`,
    permission: active.map((right) => ({
      target: options.target,
      assigner: options.assigner,
      assignee: options.assignee?.(right.licensee) ?? right.licensee,
      action: options.action ?? "use",
      constraint: [
        {
          leftOperand: "dateTime",
          operator: "gteq",
          rightOperand: dateOperand(right.startsOn),
        },
        ...(right.expiresOn === undefined
          ? []
          : [
              {
                leftOperand: "dateTime",
                operator: "lteq",
                rightOperand: dateOperand(right.expiresOn),
              },
            ]),
        ...(right.territory === undefined
          ? []
          : [
              {
                leftOperand: "spatial",
                operator: "eq",
                rightOperand: right.territory,
              },
            ]),
        ...(right.channel === undefined
          ? []
          : [
              {
                leftOperand: "purpose",
                operator: "eq",
                rightOperand: right.channel,
              },
            ]),
      ],
    })),
  };
}
