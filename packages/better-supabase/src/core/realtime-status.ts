/**
 * Supabase's release status for a Realtime feature: `beta` (public beta on
 * the platform) or `ga`.
 */
export type RealtimeStatus = "beta" | "ga";

/**
 * The status of the Realtime features a topic relies on. A private topic
 * needs Realtime Authorization for broadcast and presence, which is in
 * public beta; public broadcast, presence and Postgres changes are
 * generally available.
 */
export function topicStatus(topic: {
  readonly private?: boolean;
}): RealtimeStatus {
  return (topic.private ?? true) ? "beta" : "ga";
}
