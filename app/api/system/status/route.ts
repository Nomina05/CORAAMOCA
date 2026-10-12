import {NextResponse} from "next/server";
import {cookies} from "next/headers";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export const dynamic="force-dynamic";

export async function GET(){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const database=authDatabase();
  const {data:session}=await database.rpc("get_app_session",{p_token:token});
  if(!session?.user)return NextResponse.json({error:"Sesión inválida."},{status:401});
  const started=Date.now();
  const {error}=await database.from("app_users").select("id",{head:true,count:"exact"}).limit(1);
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
