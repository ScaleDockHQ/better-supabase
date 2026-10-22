import { dbError, err } from "better-supabase";
import * as v from "valibot";

import { bsb } from "../../lib/supabase/server";

const Body = v.object({ plan: v.string() });

/**
 * `POST /api/checkout`: starts Stripe Checkout for a plan key on the server, as
 * the caller of the bearer token. With the billing SQL module and a test-mode
 * key (`sk_test_...`), it returns `billing.checkout(organizationId, { plan,
 * successUrl, cancelUrl })`; the fixture installs neither, so it answers
 * `unsupported`.
 */
export const POST = bsb.handler(
  async (request) => {
    const body = v.safeParse(Body, await request.json());

    if (!body.success) {
      return err(dbError("invalid_input", "Pass a plan"));
    }

    return err(
      dbError(
        "unsupported",
        `Checkout for "${body.output.plan}" needs the billing SQL module and a Stripe test key, which this example doesn't install.`,
      ),
    );
  },
  { allow: ["user"] },
);
