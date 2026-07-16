import {NextResponse} from "next/server";
import {authDatabase} from "../../auth/_supabase";

export const dynamic="force-dynamic";

export async function GET(){
  const started=Date.now();
  const {error}=await authDatabase().from("app_users").select("id",{head:true,count:"exact"}).limit(1);
  const databaseAvailable=!error||error.code==="42501";
  return NextResponse.json({
    status:databaseAvailable?"operational":"degraded",
    environment:process.env.NEXT_PUBLIC_APP_ENV||process.env.VERCEL_ENV||process.env.NODE_ENV||"unknown",
    version:process.env.VERCEL_GIT_COMMIT_SHA?.slice(0,7)||process.env.NEXT_PUBLIC_APP_VERSION||"local",
    deploymentId:process.env.VERCEL_DEPLOYMENT_ID||process.env.VERCEL_URL||"",
    database:databaseAvailable?"operational":"unavailable",
    responseTimeMs:Date.now()-started,
    checkedAt:new Date().toISOString(),
  },{headers:{"Cache-Control":"no-store"}});
}
