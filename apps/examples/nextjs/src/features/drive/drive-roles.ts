/** The drive block's default node roles, weakest first. */
export const DRIVE_ROLES = ["viewer", "editor", "owner"] as const;

export type DriveRole = (typeof DRIVE_ROLES)[number];
