import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export async function GET(){const token=(await cookies()).get(sessionCookie)?.value;if(!token)return NextResponse.json({error:"No autorizado."},{status:401});const {data,error}=await authDatabase().rpc("list_hr_recruitment",{p_token:token});if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible consultar reclutamiento."},{status:403});return NextResponse.json(data)}
export async function POST(request:Request){const token=(await cookies()).get(sessionCookie)?.value;if(!token)return NextResponse.json({error:"No autorizado."},{status:401});const body=await request.json(),{data,error}=await authDatabase().rpc("manage_hr_recruitment",{p_token:token,p_action:body.action,p_data:body.data||{}});if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible completar la operación."},{status:400});return NextResponse.json(data)}
