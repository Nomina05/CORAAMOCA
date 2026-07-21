import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";
export async function POST(request:Request){
 const token=(await cookies()).get(sessionCookie)?.value;if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const body=await request.json();const {data,error}=await authDatabase().rpc("save_hr_employee_profile",{p_token:token,p_data:body});
 if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible guardar el empleado."},{status:400});return NextResponse.json(data);
}
