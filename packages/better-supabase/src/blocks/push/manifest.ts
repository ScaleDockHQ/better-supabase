import type { BlockOf } from "../define-block.ts";
import type { PushEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { pushEvents } from "./events.ts";
import { createPush } from "./push.ts";

/** The `push` block's manifest (ADR 0029). */
export const pushBlock: BlockOf<"push", typeof createPush, PushEvents> =
  defineBlock({
    name: "push",
    sql: ["push"],
    events: pushEvents,
    create: createPush,
    category: "messaging",
    entities: {
      push: { mutability: "state-machine", emits: { create: false } },
    },
    description:
      "The push tokens of each user's devices (Expo, FCM, APNs or Web Push) with RLS, behind register_push_device and unregister_push_device for the user and push_tokens_for and prune_push_tokens for the service role. With notifications, push_tickets keeps Expo's tickets per delivery for the receipt check. better-supabase/blocks/push registers Expo devices and sends through the Expo Push API.",
    recipes: ["push-opt-in"],
  });
