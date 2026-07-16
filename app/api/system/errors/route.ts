import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export async function GET(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const limit=Math.min(Number(new URL(request.url).searchParams.get("limit")||100),500);
  const {data,error}=await authDatabase().rpc("list_technical_errors",{p_token:token,p_limit:limit});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible consultar los fallos técnicos."},{status:403});
  return NextResponse.json({items:data.items||[]});
}

export async function POST(request:Request){
  const token=(await cookies()).get(sessionCookie)?.value||"";
  const body=await request.json().catch(()=>({}));
  await authDatabase().rpc("record_technical_error",{
    p_token:token,
    p_environment:process.env.NEXT_PUBLIC_APP_ENV||process.env.VERCEL_ENV||process.env.NODE_ENV||"",
    p_source:String(body.source||"Interfaz"),
    p_error_code:String(body.code||"CLIENT_ERROR"),
    p_message:String(body.message||"Error no especificado"),
    p_detail:String(body.detail||""),
    p_path:String(body.path||""),
    p_deployment_id:process.env.VERCEL_DEPLOYMENT_ID||process.env.VERCEL_GIT_COMMIT_SHA||"",
  });
  return NextResponse.json({success:true});
}
