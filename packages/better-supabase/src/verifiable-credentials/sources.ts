import type {
  CredentialConfiguration,
  CredentialSource,
} from "./openid4vci.ts";

/** A source over any lookup: the app decides which claims a subject yields. */
export function defineCredentialSource(
  source: CredentialSource,
): CredentialSource {
  return source;
}

interface SourceOptions<T> {
  /** The credential type URI wallets and verifiers match on. */
  readonly vct: string;
  readonly lookup: (subject: string) => PromiseLike<T | undefined>;
  readonly validFor?: Temporal.Duration;
  readonly display?: CredentialConfiguration["display"];
}

const optional = (
  name: string,
  value: string | undefined,
): Record<string, string> => (value === undefined ? {} : { [name]: value });

/** What the `qualifications` block's records provide. */
export interface QualificationFact {
  readonly holderName: string;
  readonly qualification: string;
  readonly issuedOn?: string;
  readonly validUntil?: string;
}

/**
 * Credentials for a held qualification. Subject references look like
 * `qualification:<id>`.
 */
export function qualificationSource(
  options: SourceOptions<QualificationFact>,
): CredentialSource {
  return {
    id: "qualifications",
    configuration: {
      id: "qualification",
      format: "dc+sd-jwt",
      vct: options.vct,
      disclosable: ["holder_name", "issued_on", "valid_until"],
      ...(options.validFor === undefined ? {} : { validFor: options.validFor }),
      ...(options.display === undefined ? {} : { display: options.display }),
    },
    async claims(subject) {
      const fact = await options.lookup(subject);

      return fact === undefined
        ? undefined
        : {
            holder_name: fact.holderName,
            qualification: fact.qualification,
            ...optional("issued_on", fact.issuedOn),
            ...optional("valid_until", fact.validUntil),
          };
    },
  };
}

/** What a course completion provides. */
export interface CourseCompletionFact {
  readonly learnerName: string;
  readonly course: string;
  readonly completedOn: string;
  readonly score?: number;
}

/**
 * Credentials for a completed course. Subject references look like
 * `course:<id>:<learner>`.
 */
export function courseCompletionSource(
  options: SourceOptions<CourseCompletionFact>,
): CredentialSource {
  return {
    id: "courses",
    configuration: {
      id: "course-completion",
      format: "dc+sd-jwt",
      vct: options.vct,
      disclosable: ["learner_name", "score"],
      ...(options.validFor === undefined ? {} : { validFor: options.validFor }),
      ...(options.display === undefined ? {} : { display: options.display }),
    },
    async claims(subject) {
      const fact = await options.lookup(subject);

      return fact === undefined
        ? undefined
        : {
            learner_name: fact.learnerName,
            course: fact.course,
            completed_on: fact.completedOn,
            ...(fact.score === undefined ? {} : { score: fact.score }),
          };
    },
  };
}

/** What an admission pass provides. */
export interface PassFact {
  readonly holderName: string;
  readonly event: string;
  readonly validFrom?: string;
  readonly validUntil?: string;
}

/** Credentials for an admission pass. Subject references look like `pass:<id>`. */
export function passSource(options: SourceOptions<PassFact>): CredentialSource {
  return {
    id: "passes",
    configuration: {
      id: "pass",
      format: "dc+sd-jwt",
      vct: options.vct,
      disclosable: ["holder_name"],
      ...(options.validFor === undefined ? {} : { validFor: options.validFor }),
      ...(options.display === undefined ? {} : { display: options.display }),
    },
    async claims(subject) {
      const fact = await options.lookup(subject);

      return fact === undefined
        ? undefined
        : {
            holder_name: fact.holderName,
            event: fact.event,
            ...optional("valid_from", fact.validFrom),
            ...optional("valid_until", fact.validUntil),
          };
    },
  };
}
