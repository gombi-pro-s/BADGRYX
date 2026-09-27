"use client";

import { useTransition } from "react";
import { deleteReportAction } from "./actions";

export function DeleteReportButton({ reportId }: { reportId: string }) {
  const [pending, startTransition] = useTransition();

  return (
    <button
      type="button"
      disabled={pending}
      onClick={() => {
        if (!confirm("Delete this report? This can't be undone.")) return;
        startTransition(() => deleteReportAction(reportId));
      }}
      className="shrink-0 text-sm font-medium text-danger hover:underline disabled:opacity-50"
    >
      {pending ? "Deleting..." : "Delete"}
    </button>
  );
}
