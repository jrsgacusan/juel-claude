/** The web app manifest the dashboard serves at /manifest.webmanifest (see handle in app.ts for the token rule). */
export function manifestFor(startUrl: string): Record<string, unknown> {
  return {
    id: "/",
    name: "STAR",
    short_name: "STAR",
    start_url: startUrl,
    scope: "/",
    display: "standalone",
    background_color: "#ffffff",
    theme_color: "#ffffff",
    icons: [
      { src: "/icons/star-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icons/star-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/icons/star-512-maskable.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
  };
}
