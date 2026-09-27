// Connection details for the LOCAL Supabase (npx supabase start). Never points at production.
import { execSync } from "node:child_process";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { createClient } = require("@supabase/supabase-js");

const status = JSON.parse(
  execSync("npx -y supabase@latest status -o json", { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] })
);

export const URL = status.API_URL;
if (!/^http:\/\/(127\.0\.0\.1|localhost)/.test(URL)) {
  throw new Error(`Refusing to run DB tests against a non-local URL: ${URL}`);
}

const options = { auth: { persistSession: false } };
export const admin = createClient(URL, status.SECRET_KEY ?? status.SERVICE_ROLE_KEY, options);
export const newUserClient = () => createClient(URL, status.PUBLISHABLE_KEY ?? status.ANON_KEY, options);
