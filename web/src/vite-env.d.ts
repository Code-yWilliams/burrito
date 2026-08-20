/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** API base URL override for local dev (e.g. http://localhost:3000). */
  readonly VITE_API_URL?: string;
}
