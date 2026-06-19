import Link from "next/link";
import { query } from "@/lib/db";
import AddTransactionForm from "./AddTransactionForm";

// This page reads live data from RDS on every request.
export const dynamic = "force-dynamic";

function money(cents: number): string {
  return (cents / 100).toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
  });
}

type CategoryRow = {
  id: string;
  name: string;
  budgeted: string;
  spent: string; // sum of outflows (positive number of cents spent)
};

type TxRow = {
  id: string;
  payee: string;
  amount: string;
  occurred_on: string;
  category_name: string | null;
};

export default async function BudgetPage() {
  const categories = await query<CategoryRow>(`
    SELECT c.id, c.name, c.budgeted,
           COALESCE(-SUM(CASE WHEN t.amount < 0 THEN t.amount ELSE 0 END), 0) AS spent
    FROM categories c
    LEFT JOIN transactions t ON t.category_id = c.id
    GROUP BY c.id, c.name, c.budgeted
    ORDER BY c.name
  `);

  const transactions = await query<TxRow>(`
    SELECT t.id, t.payee, t.amount, t.occurred_on, c.name AS category_name
    FROM transactions t
    LEFT JOIN categories c ON c.id = t.category_id
    ORDER BY t.occurred_on DESC, t.id DESC
    LIMIT 25
  `);

  const totalBudgeted = categories.reduce((s, c) => s + Number(c.budgeted), 0);
  const totalSpent = categories.reduce((s, c) => s + Number(c.spent), 0);

  return (
    <main className="container">
      <div className="brand">
        <span className="dot" />
        <Link href="/" style={{ color: "inherit", textDecoration: "none" }}>
          Budget App
        </Link>
      </div>

      <h1 style={{ fontSize: "1.8rem" }}>This month&rsquo;s budget</h1>
      <p className="muted">
        Budgeted {money(totalBudgeted)} · Spent {money(totalSpent)} · Remaining{" "}
        {money(totalBudgeted - totalSpent)}
      </p>

      <div className="card" style={{ marginTop: "1.25rem" }}>
        <table>
          <thead>
            <tr>
              <th>Category</th>
              <th>Budgeted</th>
              <th>Spent</th>
              <th>Remaining</th>
            </tr>
          </thead>
          <tbody>
            {categories.map((c) => {
              const budgeted = Number(c.budgeted);
              const spent = Number(c.spent);
              const remaining = budgeted - spent;
              return (
                <tr key={c.id}>
                  <td>{c.name}</td>
                  <td>{money(budgeted)}</td>
                  <td>{money(spent)}</td>
                  <td className={remaining < 0 ? "amount-neg" : "amount-pos"}>
                    {money(remaining)}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <h2 style={{ fontSize: "1.2rem", marginTop: "2rem" }}>Add a transaction</h2>
      <p className="muted" style={{ margin: 0, fontSize: "0.9rem" }}>
        Enter a negative amount to record spending, positive for income.
      </p>
      <AddTransactionForm
        categories={categories.map((c) => ({ id: c.id, name: c.name }))}
      />

      <h2 style={{ fontSize: "1.2rem", marginTop: "2rem" }}>Recent activity</h2>
      <div className="card">
        {transactions.length === 0 ? (
          <p className="muted" style={{ margin: 0 }}>
            No transactions yet — add one above.
          </p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Payee</th>
                <th>Category</th>
                <th>Amount</th>
              </tr>
            </thead>
            <tbody>
              {transactions.map((t) => {
                const amt = Number(t.amount);
                return (
                  <tr key={t.id}>
                    <td>{t.occurred_on}</td>
                    <td>{t.payee || <span className="muted">—</span>}</td>
                    <td>
                      {t.category_name ?? <span className="muted">—</span>}
                    </td>
                    <td className={amt < 0 ? "amount-neg" : "amount-pos"}>
                      {money(amt)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </main>
  );
}
