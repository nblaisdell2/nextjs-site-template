import { NextResponse } from "next/server";
import { query } from "@/lib/db";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

type TxRow = {
  id: string;
  payee: string;
  amount: string; // pg returns BIGINT as string
  occurred_on: string;
  category_id: string | null;
  category_name: string | null;
};

export async function GET() {
  const rows = await query<TxRow>(`
    SELECT t.id, t.payee, t.amount, t.occurred_on,
           t.category_id, c.name AS category_name
    FROM transactions t
    LEFT JOIN categories c ON c.id = t.category_id
    ORDER BY t.occurred_on DESC, t.id DESC
    LIMIT 100
  `);
  return NextResponse.json({ transactions: rows });
}

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { payee, amount, categoryId } = (body ?? {}) as {
    payee?: string;
    amount?: number | string;
    categoryId?: number | string | null;
  };

  // amount arrives as dollars; store cents.
  const dollars = Number(amount);
  if (!Number.isFinite(dollars) || dollars === 0) {
    return NextResponse.json(
      { error: "amount must be a non-zero number (dollars)" },
      { status: 400 }
    );
  }
  const cents = Math.round(dollars * 100);

  const rows = await query<{ id: string }>(
    `INSERT INTO transactions (payee, amount, category_id)
     VALUES ($1, $2, $3)
     RETURNING id`,
    [
      (payee ?? "").toString().slice(0, 200),
      cents,
      categoryId ? Number(categoryId) : null,
    ]
  );

  return NextResponse.json({ id: rows[0]?.id }, { status: 201 });
}
