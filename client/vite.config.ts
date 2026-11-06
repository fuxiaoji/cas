import { fileURLToPath } from 'node:url';
import { defineConfig, loadEnv } from 'vite';

export default defineConfig(({ command, mode }) => {
  const localRadio = command === 'serve' || loadEnv(mode, process.cwd(), 'VITE_CAS_').VITE_CAS_LOCAL_VOICE === '1';
  return {
    base: './',
    build: { target: 'es2022' },
    server: { host: '127.0.0.1', strictPort: true },
    define: { __CAS_LOCAL_RADIO__: JSON.stringify(localRadio) },
    resolve: { alias: {
      'virtual:cas-fleet-radio-clips': fileURLToPath(new URL(localRadio ? './src/audio/localRadioClips.ts' : './src/audio/noRadioClips.ts', import.meta.url)),
    } },
  };
});
