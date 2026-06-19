"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

type Category = { id: string; name: string };

export default function AddTransactionForm({
  categories,
}: {
  categories: Category[];
}) {
  const router = useRouter();
  const [payee, setPayee] = useState("");
  const [amount, setAmount] = useState("");
  const [categoryId, setCategoryId] = useState<string>("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/transactions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          payee,
          amount,
          categoryId: categoryId || null,
        }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? `Request failed (${res.status})`);
      }
      setPayee("");
      setAmount("");
      setCategoryId("");
      router.refresh(); // re-runs the server component to show the new row
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="row" onSubmit={submit}>
      <input
        aria-label="Payee"
        placeholder="Payee (e.g. Whole Foods)"
        value={payee}
        onChange={(e) => setPayee(e.target.value)}
        style={{ flex: "2 1 180px" }}
      />
      <input
        aria-label="Amount in dollars"
        placeholder="Amount (− to spend)"
        inputMode="decimal"
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
        style={{ flex: "1 1 120px" }}
      />
      <select
        aria-label="Category"
        value={categoryId}
        onChange={(e) => setCategoryId(e.target.value)}
        style={{ flex: "1 1 140px" }}
      >
        <option value="">No category</option>
        {categories.map((c) => (
          <option key={c.id} value={c.id}>
            {c.name}
          </option>
        ))}
      </select>
      <button className="btn" type="submit" disabled={busy}>
        {busy ? "Adding…" : "Add"}
      </button>
      {error && (
        <span className="amount-neg" style={{ flexBasis: "100%" }}>
          {error}
        </span>
      )}
    </form>
  );
}
