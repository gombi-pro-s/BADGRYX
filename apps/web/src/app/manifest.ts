import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "iCorePen",
    short_name: "iCorePen",
    description:
      "iCorePen is a cybersecurity learning, security-analysis, cyber-range, CTF, OSINT, and AI-assisted security platform.",
    start_url: "/dashboard",
    display: "standalone",
    background_color: "#0a0d12",
    theme_color: "#0a0d12",
    icons: [
      { src: "/icons/192", sizes: "192x192", type: "image/png" },
      { src: "/icons/512", sizes: "512x512", type: "image/png" },
    ],
  };
}
