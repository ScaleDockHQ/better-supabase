"use server";

import { dbError, err, ok } from "better-supabase";
import { refresh } from "next/cache";
import { headers } from "next/headers";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

import { connectCredentials, integrationOf } from "./integrations-server";

const Input = v.object({ id: v.picklist(["gmail", "outlook"]) });

/** Where Vercel Connect sends the user back to after consent. */
const CALLBACK_PATH = "/api/integrations/callback";

/**
 * Starts the Connect consent flow for the signed-in user and returns the URL to
 * send them to. The redirect URI comes from the request's own origin, which
 * Next.js has already checked against the host for a Server Action.
 */
export const connectIntegration = bsb.action(
  { input: Input },
  async ({ id }, { session }) => {
    const integration = integrationOf(id);

    if (integration === undefined || session.kind !== "user") {
      return err(dbError("not_found", "This integration isn't set up"));
    }

    const origin = (await headers()).get("origin");

    if (origin === null) {
      return err(dbError("invalid_input", "The request has no origin"));
    }

    const redirectUri = new URL(CALLBACK_PATH, origin);
    redirectUri.searchParams.set("integration", id);

    const started = await connectCredentials().startAuthorization?.(
      integration.ref,
      {
        subject: { type: "user", id: session.user.id },
        redirectUri: redirectUri.href,
      },
    );

    if (started === undefined) {
      return err(dbError("invalid_input", "Connect can't start consent"));
    }

    return started.ok ? ok(started.data.url) : started;
  },
);

/** Revokes the user's grant at Connect, so the next read asks for consent. */
export const disconnectIntegration = bsb.action(
  { input: Input },
  async ({ id }, { session }) => {
    const integration = integrationOf(id);

    if (integration === undefined || session.kind !== "user") {
      return err(dbError("not_found", "This integration isn't set up"));
    }

    const revoked = await connectCredentials().revoke(integration.ref, {
      subject: { type: "user", id: session.user.id },
    });

    if (!revoked.ok) {
      return revoked;
    }

    refresh();

    return ok(revoked.data);
  },
);
