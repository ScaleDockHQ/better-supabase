/**
 * Labels a seed writes, in en, nl and de. `variant` on the seed function is the
 * brand. Stable keys stay the same in every locale; the text changes.
 */
export const SEED_LOCALES = ["en", "nl", "de"] as const;

export interface SeedLabel {
  readonly key: string;
  readonly locales: Readonly<Record<(typeof SEED_LOCALES)[number], string>>;
}

export const LETTERHEADS: SeedLabel = {
  key: "letterhead",
  locales: {
    en: "{{entity.name}} · Company no. {{entity.cocNumber}} · VAT {{entity.vatNumber}} · IBAN {{entity.iban}}",
    nl: "{{entity.name}} · KvK {{entity.cocNumber}} · BTW {{entity.vatNumber}} · IBAN {{entity.iban}}",
    de: "{{entity.name}} · Handelsregister {{entity.cocNumber}} · USt-IdNr. {{entity.vatNumber}} · IBAN {{entity.iban}}",
  },
};

/** English names for the shared tax keys. Country packs add their own codes. */
export const TAX_LABELS: readonly SeedLabel[] = [
  {
    key: "STD",
    locales: { en: "Standard VAT", nl: "Standaard btw", de: "Regelsteuersatz" },
  },
  {
    key: "RED",
    locales: {
      en: "Reduced VAT",
      nl: "Verlaagd btw-tarief",
      de: "Ermäßigter Steuersatz",
    },
  },
  {
    key: "ZERO",
    locales: { en: "Zero rate", nl: "Nultarief", de: "Nullsatz" },
  },
];

export const SEED_LABELS: readonly SeedLabel[] = [LETTERHEADS, ...TAX_LABELS];
