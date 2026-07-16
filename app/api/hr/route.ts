import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../auth/_supabase";

export async function GET(){
  const token=(await cookies()).get(sessionCookie)?.value;
  if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
  const {data,error}=await authDatabase().rpc("list_hr_employees",{p_token:token});
  if(error||!data?.success)return NextResponse.json({error:data?.error||"No fue posible cargar Recursos Humanos."},{status:403});
  return NextResponse.json({employees:data.employees||[]});
}
