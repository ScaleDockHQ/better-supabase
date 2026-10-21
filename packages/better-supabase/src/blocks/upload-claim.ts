import type { DbError } from "../core/errors.ts";

import { dbError } from "../core/errors.ts";
import { AsyncResult, err, ok } from "../core/result.ts";
import { fromStorageError } from "../storage/errors.ts";

/** The claim step of a Storage API, such as the one `supportStorage` returns. */
export interface UploadClaimStorage {
  claimSignedUpload?(
    bucket: string,
    path: string,
  ): PromiseLike<{ readonly data: unknown; readonly error: unknown }>;
}

/** The hints a block puts on a refused claim. */
interface UploadClaimHints {
  readonly notUploaded: string;
  readonly forbidden: string;
}

function refusal(cause: unknown, hints: UploadClaimHints): DbError {
  const error = fromStorageError(cause, "storage.objects");

  if (error.kind === "not_found") {
    return dbError("not_found", "The file was not uploaded yet", {
      hint: hints.notUploaded,
    });
  }

  if (error.kind === "forbidden") {
    return dbError("forbidden", error.message, {
      hint: hints.forbidden,
      ...(error.code === undefined ? {} : { code: error.code }),
    });
  }

  return error;
}

/**
 * Claims an object a browser uploaded to a signed upload URL, so a support
 * session records it. Succeeds without a request when the storage has no claim
 * step.
 */
export function claimUpload(
  storage: UploadClaimStorage,
  file: { readonly bucket: string; readonly path: string },
  hints: UploadClaimHints,
): AsyncResult<void> {
  return AsyncResult.from(async () => {
    if (!storage.claimSignedUpload) {
      return ok(undefined);
    }

    try {
      const { error } = await storage.claimSignedUpload(file.bucket, file.path);

      return error ? err(refusal(error, hints)) : ok(undefined);
    } catch (cause) {
      return err(refusal(cause, hints));
    }
  });
}

/** Whether `storage` has a claim step, so a block needs the file's path first. */
export const claimsUploads = (storage: UploadClaimStorage): boolean =>
  storage.claimSignedUpload !== undefined;
