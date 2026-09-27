import { ImageResponse } from "next/og";

export const dynamic = "force-static";

export function GET() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "#0a0d12",
          color: "#2dd4bf",
          fontSize: 116,
          fontWeight: 700,
        }}
      >
        &gt;
      </div>
    ),
    { width: 192, height: 192 },
  );
}
