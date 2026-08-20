import { useEffect, useState } from "react";

const API_URL = import.meta.env.VITE_API_URL ?? "https://api-burrito.moldysandwich.com";

type FetchState =
  | { phase: "loading" }
  | { phase: "done"; status: number; body: string }
  | { phase: "error"; message: string };

export default function App() {
  const [state, setState] = useState<FetchState>({ phase: "loading" });

  useEffect(() => {
    fetch(`${API_URL}/healthz`)
      .then(async (res) =>
        setState({
          phase: "done",
          status: res.status,
          body: JSON.stringify(await res.json(), null, 2),
        }),
      )
      .catch((err: unknown) =>
        setState({
          phase: "error",
          message: err instanceof Error ? err.message : String(err),
        }),
      );
  }, []);

  return (
    <main style={{ fontFamily: "monospace", padding: "2rem" }}>
      <h1>burrito</h1>
      <p>
        <code>GET {API_URL}/healthz</code>
      </p>
      {state.phase === "loading" && <p>loading…</p>}
      {state.phase === "error" && <p>request failed: {state.message}</p>}
      {state.phase === "done" && (
        <pre>
          HTTP {state.status}
          {"\n"}
          {state.body}
        </pre>
      )}
    </main>
  );
}
