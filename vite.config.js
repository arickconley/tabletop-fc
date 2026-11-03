import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

export default defineConfig({
  resolve: {
    // Keep using the checked-in Three.js files, including OrbitControls.
    alias: [
      {
        find: /^three$/,
        replacement: fileURLToPath(
          new URL("./vendor/three/three.module.js", import.meta.url),
        ),
      },
      {
        find: "three/addons/controls/OrbitControls.js",
        replacement: fileURLToPath(
          new URL("./vendor/three/OrbitControls.js", import.meta.url),
        ),
      },
    ],
  },
  server: {
    host: "0.0.0.0",
    port: 8000,
    // Saved matches are tied to the origin; don't silently switch ports.
    strictPort: true,
  },
});
