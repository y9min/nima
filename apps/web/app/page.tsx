import { redirect } from "next/navigation";
import { connection } from "next/server";
import { createClient } from "@/lib/supabase/server";
import SignOutButton from "./sign-out-button";

export default async function Home() {
  await connection();

  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();

  if (!data?.claims) {
    redirect("/login");
  }

  return (
    <div style={{ maxWidth: 600, margin: "100px auto", fontFamily: "system-ui" }}>
      <h1>Bubble</h1>
      <p>
        Logged in as <strong>{data.claims.email as string}</strong>
      </p>
      <SignOutButton />
    </div>
  );
}
