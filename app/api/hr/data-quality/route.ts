import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export async function GET(){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const {data,error}=await authDatabase().rpc("list_hr_data_quality",{p_token:token});
 if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible validar la calidad de los datos."},{status:403});
 return NextResponse.json(data);
}
