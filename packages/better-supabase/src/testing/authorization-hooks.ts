import type { AuthorizationHooks } from "../core/contracts/authorization-hooks.ts";

import { type ConformanceReport, conform, expect } from "./conformance.ts";

/**
 * Proves `AuthorizationHooks` target API v1 and fail closed for strangers:
 * fan-out returns only subscribers it was given, an identity nobody linked
 * and a forged ticket resolve to `null`, a requester never approves their
 * own request, an unknown publisher and an unlinked chat author get
 * nothing, an admin with no claims cannot start a support session, and a
 * delegated token with no scopes maps to no permissions.
 */
export function testAuthorizationHooks(
  hooks: AuthorizationHooks,
): Promise<ConformanceReport> {
  const stranger = crypto.randomUUID();
  const event = {
    type: "conformance.checked",
    tenant: crypto.randomUUID(),
    actorId: stranger,
    payload: {},
  };
  const subscribers = [
    { principal: crypto.randomUUID(), kind: "user" as const },
    { principal: crypto.randomUUID(), kind: "service" as const },
  ];
  const subset = async (
    policy: NonNullable<
      NonNullable<AuthorizationHooks["delivery"]>["subscribers"]
    >,
    where: string,
  ): Promise<void> => {
    const kept = await policy(event, subscribers);
    for (const entry of kept)
      expect(
        subscribers.includes(entry),
        `${where} returned a subscriber it was not given`,
      );
    expect(
      (await policy(event, [])).length === 0,
      `${where} returned subscribers from an empty list`,
    );
  };
  const {
    delivery,
    identities,
    approverOf,
    tickets,
    automation,
    chat,
    delegation,
  } = hooks;
  return conform(`AuthorizationHooks "${hooks.name}"`, [
    [
      "targets API v1 and has a name",
      () => {
        expect(
          // oxlint-disable-next-line typescript/no-unnecessary-condition -- the kit checks hooks written in JavaScript too.
          hooks.apiVersion === 1,
          `apiVersion is ${String(hooks.apiVersion)}`,
        );
        expect(hooks.name !== "", "name is empty");
      },
    ],
    delivery?.subscribers && [
      "subscribers returns a subset",
      () => subset(delivery.subscribers!, "delivery.subscribers"),
    ],
    delivery?.audience && [
      "audience returns a subset",
      () => subset(delivery.audience!, "delivery.audience"),
    ],
    identities && [
      "an unlinked identity is null",
      async () => {
        const found = await identities.principalByIdentity({
          kind: "email",
          value: `${stranger}@conformance.invalid`,
        });
        expect(found === null, "an address nobody linked resolved to someone");
      },
    ],
    approverOf && [
      "a requester never approves their own request",
      async () => {
        const allowed = await approverOf(
          { userId: stranger, claims: { sub: stranger } },
          {
            kind: "tool",
            subject: crypto.randomUUID(),
            tenant: event.tenant,
            requester: stranger,
          },
        );
        expect(!allowed, "approverOf allowed the requester");
      },
    ],
    tickets && [
      "a forged ticket is null",
      async () => {
        const context = await tickets.subject(`forged.${stranger}.ticket`);
        expect(context === null, "a forged ticket resolved to a context");
      },
    ],
    automation?.runAs && [
      "an unknown publisher runs as no one",
      async () => {
        const claims = await automation.runAs!({
          publisher: stranger,
          tenant: event.tenant,
          permissions: ["conformance.read"],
        });
        expect(
          claims === null,
          "runAs returned claims for an unknown publisher",
        );
      },
    ],
    chat?.onAction && [
      "an unlinked chat author is refused",
      async () => {
        const decided = await chat.onAction!(
          {
            id: "approve",
            author: { kind: "chat", provider: "conformance", value: stranger },
          },
          null,
        );
        expect(
          decided === undefined || !decided.allowed,
          "onAction allowed an author with no identity link",
        );
      },
    ],
    hooks.support && [
      "an admin with no claims cannot start a support session",
      async () => {
        const claims = {
          sub: stranger,
          role: "authenticated",
          aud: "authenticated",
          iss: "conformance",
          exp: Math.floor(Date.now() / 1000) + 60,
          iat: Math.floor(Date.now() / 1000),
        };
        const decision = await hooks.support!.authorize({
          admin: {
            kind: "user",
            token: "",
            claims,
            user: { id: stranger, role: "authenticated" },
            source: "conformance",
            expiresAt: claims.exp,
          },
          targetUserId: crypto.randomUUID(),
          reason: "conformance",
          readOnly: true,
          metadata: {},
        });
        expect(
          decision === false,
          "support.authorize allowed an admin with no claims",
        );
      },
    ],
    delegation && [
      "a delegation with no scopes grants no permissions",
      async () => {
        const keys = await delegation.permissions({
          userId: stranger,
          tenant: event.tenant,
          clientId: "conformance",
          scopes: [],
        });
        expect(
          keys.length === 0,
          "delegation.permissions granted keys to a token with no scopes",
        );
      },
    ],
  ]);
}
