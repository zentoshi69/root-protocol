import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

// Kept separate from vite.config.ts: vitest's `test` field is not part of Vite's own config type,
// and merging them means the build config only typechecks by accident.
export default defineConfig({
  plugins: [react()],
  test: {
    // jsdom rather than node, so the cold-wallet download path (Blob + createObjectURL) is
    // exercised for real instead of mocked away.
    environment: 'jsdom',
    globals: true,
  },
});
