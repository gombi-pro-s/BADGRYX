"use client";

import { useEffect } from "react";

export function RegisterServiceWorker() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;
    navigator.serviceWorker.register("/sw.js").catch(() => {
      // Offline support is a progressive enhancement -- a registration
      // failure (unsupported browser, blocked storage) should never break
      // the app itself.
    });
  }, []);

  return null;
}
