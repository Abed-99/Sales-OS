import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

export async function createClient() {
  const store = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() {
          return store.getAll();
        },

        setAll(items) {
          try {
            items.forEach(
              ({ name, value, options }) =>
                store.set(name, value, options)
            );
          } catch (error) {
            if (process.env.NODE_ENV === "development") {
              console.warn(
                "Supabase cookie update skipped in this server context.",
                error
              );
            }
          }
        },
      },
    }
  );
}

