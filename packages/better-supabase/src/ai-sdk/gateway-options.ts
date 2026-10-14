import type { JSONValue } from "ai";

/** Who a generation is for, as the AI Gateway reports spend. */
export interface GatewayContext {
  readonly userId?: string;
  readonly organizationId?: string;
  readonly chatId?: string;
  /** What the generation is for, such as `chat` or `summary`. */
  readonly feature?: string;
  /** The app's own tags, after the tenant, chat and feature tags. */
  readonly tags?: readonly string[];
}

/** The AI Gateway's own options (`providerOptions.gateway`). */
export type GatewayOptions = { readonly [key: string]: JSONValue | undefined };

/**
 * `providerOptions` for `streamText` and agents that attribute the spend in
 * the AI Gateway: `user` is the user id, and `tags` name the tenant, the chat
 * and the feature, then the context's own `tags`. `extra` adds gateway
 * options such as `order` or `zeroDataRetention`; its `tags` are appended.
 * `user` comes from `context.userId` only: an `extra.user` is dropped, so a
 * request body or a model can't change whom the spend is attributed to.
 */
export function gatewayOptions(
  context: GatewayContext,
  extra: GatewayOptions = {},
): { readonly gateway: GatewayOptions } {
  const tags: string[] = [];
  if (context.organizationId !== undefined)
    tags.push(`org:${context.organizationId}`);
  if (context.chatId !== undefined) tags.push(`chat:${context.chatId}`);
  if (context.feature !== undefined) tags.push(`feature:${context.feature}`);
  if (context.tags !== undefined) tags.push(...context.tags);
  const more = extra["tags"];
  if (Array.isArray(more))
    for (const tag of more) if (typeof tag === "string") tags.push(tag);
  const options: GatewayOptions = Object.fromEntries(
    Object.entries(extra).filter(([key]) => key !== "user" && key !== "tags"),
  );
  return {
    gateway: {
      ...options,
      ...(context.userId === undefined ? {} : { user: context.userId }),
      ...(tags.length === 0 ? {} : { tags }),
    },
  };
}
