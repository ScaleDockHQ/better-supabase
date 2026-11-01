import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { InvitationSent } from "../organizations/index.ts";
import type { SaasParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult as Async, err } from "../../core/result.ts";

/** The helpers `saas` adds over its parts. */
export interface Saas {
  /**
   * Invites `email` when the organization has a seat left: it counts the
   * members, reads the `seats` entitlement and only then calls
   * `organizations.invite`. A plan without a `seats` limit has no cap. Pending
   * invitations do not count, so an app that caps them lists them first.
   */
  inviteWithinSeats(input: {
    organizationId: string;
    email: string;
    role: string;
    validFor?: string | undefined;
  }): AsyncResult<InvitationSent>;
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
  const { organizations, entitlements } = options.parts;

  const client: Saas = {
    inviteWithinSeats: ({ organizationId, email, role, validFor }) =>
      Async.from(async () => {
        const members = await organizations.members(organizationId);

        if (!members.ok) {
          return members;
        }

        const left = await entitlements.seatsLeft({
          organizationId,
          used: members.data.length,
        });

        if (!left.ok) {
          return left;
        }

        if (left.data !== undefined && left.data <= 0) {
          return err(dbError("invalid_request", "The plan has no seat left"));
        }

        return organizations.invite({
          organizationId,
          email,
          role,
          ...(validFor === undefined ? {} : { validFor }),
        });
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "saas",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
