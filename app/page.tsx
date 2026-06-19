import Link from "next/link";

export default function Home() {
  return (
    <main className="container">
      <div className="brand">
        <span className="dot" />
        Budget App
      </div>

      <h1>Give every dollar a job.</h1>
      <p className="muted" style={{ maxWidth: 560 }}>
        A YNAB-style budgeting app scaffold. Full server-side Next.js, running
        in a container on AWS App Runner, talking to PostgreSQL on RDS, with
        credentials held in Secrets Manager.
      </p>

      <p style={{ marginTop: "1.5rem" }}>
        <Link className="btn" href="/budget">
          Open the budget &rarr;
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
            Accessed over a private VPC connector via the node-postgres pool.
          </p>
        </div>
        <div className="card">
          <span className="pill">Hosting</span>
          <h3 style={{ margin: "0.6rem 0 0.3rem" }}>AWS App Runner</h3>
          <p className="muted" style={{ margin: 0 }}>
            Pulls the image from ECR, autoscales, and health-checks{" "}
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
