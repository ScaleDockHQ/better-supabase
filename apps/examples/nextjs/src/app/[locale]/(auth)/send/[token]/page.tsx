import { Suspense } from "react";

import {
  FileRequestUpload,
  FileRequestUploadSkeleton,
} from "@/features/drive/components/file-request-upload";

async function FileRequestRoute({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;

  return <FileRequestUpload token={token} />;
}

export default function SendPage({
  params,
}: PageProps<"/[locale]/send/[token]">) {
  return (
    <Suspense fallback={<FileRequestUploadSkeleton />}>
      <FileRequestRoute params={params} />
    </Suspense>
  );
}
