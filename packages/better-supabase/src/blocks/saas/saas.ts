import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { CreatedApiKey } from "../api-keys/index.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions, PartClients } from "../define-block.ts";
import type { InvitationSent } from "../organizations/index.ts";
import type { SaasParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult as Async, err } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";

type SaasClients = PartClients<SaasParts>;

/** The helpers `saas` adds over its parts. */
export interface Saas {
  /**
   * Invites `email` when the organization has a seat left, in one database call
   * (`organizations.inviteWithinSeats`, ADR 1235): the members are counted
   * against the `seats` entitlement in the same transaction as the invitation.
   * A plan without a `seats` limit has no cap. Pending invitations do not
   * count, so an app that caps them lists them first.
   */
  inviteWithinSeats(input: {
    organizationId: string;
    email: string;
    role: string;
    validFor?: string | undefined;
  }): AsyncResult<InvitationSent>;
  /**
   * Rotates an API key (`apiKeys.rotate`) and lets the old token work for
   * `graceHours` more hours (24 by default, 0 to 720). The new token is in the
   * result once; show it to the caller and never store it.
   */
  rotateApiKey(input: {
    id: string;
    graceHours?: number | undefined;
  }): AsyncResult<CreatedApiKey>;
}

const MAX_GRACE_HOURS = 720;

/**
 * `rotateApiKey` over the `api-keys` client alone, for an app that installs the
 * key block without the rest of `saas`.
 */
export function createKeyRotator({
  apiKeys,
}: {
  readonly apiKeys: Pick<SaasClients["api-keys"], "rotate">;
}): Pick<Saas, "rotateApiKey"> {
  return {
    rotateApiKey: ({ id, graceHours = 24 }) =>
      Async.from(async () => {
        if (
          !Number.isInteger(graceHours) ||
          graceHours < 0 ||
          graceHours > MAX_GRACE_HOURS
        ) {
          return err(
            dbError(
              "invalid_request",
              `graceHours is a whole number from 0 to ${MAX_GRACE_HOURS}`,
            ),
          );
        }

        return apiKeys.rotate({
          id,
          grace: temporal().Duration.from({ hours: graceHours }),
        });
      }),
  };
}

/** What the `saas` creator receives. */
export type SaasOptions = BlockContext &
  CompositeOptions<SaasParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Saas>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `saas` helpers over the clients of its parts. */
export function createSaas(options: SaasOptions): Saas {
  const { organizations, "api-keys": apiKeys } = options.parts;

  const client: Saas = {
    inviteWithinSeats: ({ organizationId, email, role, validFor }) =>
      organizations.inviteWithinSeats({
        organizationId,
        email,
        role,
        ...(validFor === undefined ? {} : { validFor }),
      }),
    ...createKeyRotator({ apiKeys }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "saas",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
