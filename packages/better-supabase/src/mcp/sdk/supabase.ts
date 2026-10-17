import type { AuthState } from "../../auth/resolve.ts";
import type {
  SupabaseMcpModule,
  SupabaseMcpPlatformModule,
  SupabaseMcpScope,
} from "../../core/supabase-mcp.ts";
import type {
  CredentialProvider,
  CredentialRef,
} from "../../credentials/provider.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";
import type { BetterMcpAuth } from "./sdk.ts";

import { dbError } from "../../core/errors.ts";
import { problemResponse } from "../../core/problem.ts";
import {
  isRecord,
  loadSupabaseMcp,
  loadSupabaseMcpPlatform,
} from "../../core/supabase-mcp.ts";
import { MCP_AUTH_STATE_KEY } from "./sdk.ts";

type UserAuth<C, P> = Extract<AuthState<C, P>, { kind: "user" }>;

export interface SupabaseMcpHandlerOptions<
  C = unknown,
  P = unknown,
> extends SupabaseMcpScope {
  /** Resolves the Management API token, as the app; never the caller's JWT. */
  readonly credentials: CredentialProvider;
  /** The app credential that holds a Management API access token. */
  readonly credentialRef: CredentialRef;
  /**
   * Who may use the server once the bearer token verified. Its tools
   * administer the project, so allow only the people who run it.
   */
  readonly authorize: (auth: UserAuth<C, P>) => boolean | Promise<boolean>;
  /** The Management API URL; Supabase's when unset. */
  readonly apiUrl?: string;
}

/** Loads `@supabase/mcp-server-supabase`; tests pass their own. */
export interface SupabaseMcpLoaders {
  readonly server?: () => Promise<SupabaseMcpModule>;
  readonly platform?: () => Promise<SupabaseMcpPlatformModule>;
}

function userOf<C, P>(authInfo: unknown): UserAuth<C, P> | undefined {
  if (!isRecord(authInfo) || !isRecord(authInfo["extra"])) {
    return undefined;
  }

  const state = authInfo["extra"][MCP_AUTH_STATE_KEY];

  // SAFETY: auth.serve puts the AuthState its verifier resolved under this key.
  return isRecord(state) && state["kind"] === "user"
    ? (state as UserAuth<C, P>)
    : undefined;
}

/** The response, with `done` called once its body is read, cancelled or fails. */
function onFinish(response: Response, done: () => void): Response {
  const source = response.body;

  if (source === null) {
    done();

    return response;
  }

  const reader = source.getReader();

  const body = new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        const chunk = await reader.read();

        if (chunk.done) {
          controller.close();
          done();
        } else {
          controller.enqueue(chunk.value);
        }
      } catch (error) {
        controller.error(error);
        done();
      }
    },
    cancel(reason) {
      done();

      return reader.cancel(reason);
    },
  });

  return new Response(body, {
    status: response.status,
    statusText: response.statusText,
    headers: response.headers,
  });
}

/**
 * Serves Supabase's MCP server (`@supabase/mcp-server-supabase`) behind
 * `createMcpAuth`: the bearer check and metadata of `auth.serve`, then
 * `authorize`, then a server built for the request with the Management API
 * token from `credentials`. The server closes when its response ends.
 */
export function supabaseMcpHandler<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(
  auth: Pick<BetterMcpAuth<M, F, E, C, P>, "serve">,
  options: SupabaseMcpHandlerOptions<C, P>,
  loaders: SupabaseMcpLoaders = {},
): (request: Request) => Promise<Response> {
  const loadServer = loaders.server ?? loadSupabaseMcp;
  const loadPlatform = loaders.platform ?? loadSupabaseMcpPlatform;

  return auth.serve({
    async fetch(request, init) {
      const user = userOf<C, P>(init?.authInfo);

      if (user === undefined || !(await options.authorize(user))) {
        return problemResponse(
          dbError("forbidden", "Supabase's MCP server is not open to you"),
        );
      }

      const token = await options.credentials.getToken(options.credentialRef, {
        subject: { type: "app" },
      });

      if (!token.ok) {
        return problemResponse(token.error);
      }

      const [server, platform] = await Promise.all([
        loadServer(),
        loadPlatform(),
      ]);

      const handler = server.createSupabaseMcpHandler({
        platform: platform.createSupabaseApiPlatform({
          accessToken: token.data.token,
          ...(options.apiUrl === undefined ? {} : { apiUrl: options.apiUrl }),
        }),
        readOnly: options.readOnly ?? true,
        ...(options.projectRef === undefined
          ? {}
          : { projectId: options.projectRef }),
        ...(options.features === undefined
          ? {}
          : { features: [...options.features] }),
      });

      let closed = false;

      const close = (): void => {
        if (closed) {
          return;
        }

        closed = true;
        void handler.close().catch(() => {});
      };

      try {
        return onFinish(await handler.fetch(request, init), close);
      } catch (error) {
        close();
        throw error;
      }
    },
  });
}
