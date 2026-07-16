import { createClient } from "@supabase/supabase-js";
import {validateEnvironment} from "../../lib/environment";

export const authDatabase = () => {
  const environment=validateEnvironment();
  return createClient(
  environment.supabaseUrl,
  environment.publishableKey,
  { auth: { persistSession: false, autoRefreshToken: false } },
  );
};

export const sessionCookie = "coraamoca_session";
export const cookieOptions = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "lax" as const,
  path: "/",
  maxAge: 60 * 60 * 12,
};
