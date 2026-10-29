/** The roles a representative takes in a `represents` link's `data.role`. */
export const REPRESENTATIVE_ROLES = [
  "legal_representative",
  "guardian",
  "mentor",
  "curator",
  "parent",
  "contact_person",
  "emergency_contact",
  "other",
] as const;

export type RepresentativeRole = (typeof REPRESENTATIVE_ROLES)[number];

/** `inform`: kept informed. `act`: acts for the record, as a guest too. */
export const REPRESENTATIVE_AUTHORITIES = ["inform", "act"] as const;

export type RepresentativeAuthority =
  (typeof REPRESENTATIVE_AUTHORITIES)[number];
