import { Suspense } from "react";

import {
  FileRequestUpload,
  FileRequestUploadSkeleton,
} from "@/features/drive/components/file-request-upload";

export default function SendPage({
  params,
}: PageProps<"/[locale]/send/[token]">) {
  return (
    <Suspense fallback={<FileRequestUploadSkeleton />}>
      {params.then(({ token }) => (
        <FileRequestUpload token={token} />
      ))}
    </Suspense>
  );
}
