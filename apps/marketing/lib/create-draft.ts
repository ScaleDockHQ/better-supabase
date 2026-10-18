import * as v from "valibot";

/** The last design on `/create`, so a visit without a link can bring it back. */
export interface CreateDraft {
  /** `encodePreset` of the preset. */
  readonly preset: string;
  /** `encodeDesign` of the design; never empty in a saved draft. */
  readonly design: string;
}

const DRAFT_KEY = "better-supabase:create-draft:v1";

const draftSchema = v.object({
  preset: v.pipe(v.string(), v.maxLength(2000)),
  design: v.pipe(v.string(), v.minLength(1), v.maxLength(6000)),
});

/** The saved draft, or `undefined` when there is none or storage is off. */
export function readDraft(storage: Storage): CreateDraft | undefined {
  try {
    const raw = storage.getItem(DRAFT_KEY);

    if (raw === null) {
      return undefined;
    }

    const parsed = v.safeParse(draftSchema, JSON.parse(raw));

    return parsed.success ? parsed.output : undefined;
  } catch {
    return undefined;
  }
}

/** Saves the draft; storage that throws (private mode, quota) is ignored. */
export function writeDraft(storage: Storage, draft: CreateDraft): void {
  try {
    storage.setItem(DRAFT_KEY, JSON.stringify(draft));
  } catch {
    // The draft is a convenience; the URL still carries the design.
  }
}

export function clearDraft(storage: Storage): void {
  try {
    storage.removeItem(DRAFT_KEY);
  } catch {
    // See writeDraft.
  }
}
