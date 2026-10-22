/** What a guest grant allows on a record. */
export type GuestAction = "read" | "comment" | "upload";

/** Every guest action, in the order the grants store them. */
export const GUEST_ACTIONS: readonly GuestAction[] = [
  "read",
  "comment",
  "upload",
];
