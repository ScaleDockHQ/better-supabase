import type {
  AttachmentUploadState,
  UseAttachmentUploadOptions,
} from "./index.ts";

export type {
  AttachmentUploadState,
  UseAttachmentUploadOptions,
} from "./index.ts";

/**
 * The `react-server` build of `useAttachmentUpload`: call
 * `attachments.upload()` in a server action instead.
 */
export const useAttachmentUpload: (
  options: UseAttachmentUploadOptions,
) => AttachmentUploadState = () => {
  throw new Error(
    "better-supabase: useAttachmentUpload() runs in Client Components only. In Server Components call `attachments.upload()` in a server action instead.",
  );
};
