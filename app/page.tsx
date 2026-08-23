import Link from "next/link";

export default function Home() {
  return (
    <main className="container">
      <div className="brand">
        <span className="dot" />
        Site Template
      </div>

      <h1>Ship a full-stack Next.js site on AWS.</h1>
      <p className="muted" style={{ maxWidth: 560 }}>
        A generic starting point for any project: full server-side Next.js,
        running in a container on Amazon ECS (Express Mode), talking to
        PostgreSQL on RDS, with credentials held in Secrets Manager.
      </p>

      <p style={{ marginTop: "1.5rem" }}>
        <Link className="btn" href="/demo">
          Open the database demo &rarr;
        </Link>
      </p>

      <div className="grid">
        <div className="card">
          <span className="pill">Frontend + API</span>
          <h3 style={{ margin: "0.6rem 0 0.3rem" }}>Next.js (App Router)</h3>
          <p className="muted" style={{ margin: 0 }}>
            Server components and route handlers, built as a standalone server
            image.
          </p>
        </div>
        <div className="card">
          <span className="pill">Database</span>
          <h3 style={{ margin: "0.6rem 0 0.3rem" }}>PostgreSQL on RDS</h3>
          <p className="muted" style={{ margin: 0 }}>
            Accessed via the node-postgres pool with the connection string
            injected from Secrets Manager.
          </p>
        </div>
        <div className="card">
          <span className="pill">Hosting</span>
          <h3 style={{ margin: "0.6rem 0 0.3rem" }}>Amazon ECS Express Mode</h3>
          <p className="muted" style={{ margin: 0 }}>
            Pulls the image from ECR, fronts it with an ALB, and health-checks{" "}
            <code>/api/health</code>.
          </p>
        </div>
      </div>

      <p className="muted" style={{ marginTop: "2rem", fontSize: "0.85rem" }}>
        Health endpoint: <Link href="/api/health">/api/health</Link>
      </p>
    </main>
  );
}
