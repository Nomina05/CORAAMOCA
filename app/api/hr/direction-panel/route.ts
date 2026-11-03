import {cookies} from "next/headers";
import {NextResponse} from "next/server";
import {authDatabase,sessionCookie} from "../../auth/_supabase";

export async function GET(request:Request){
 const token=(await cookies()).get(sessionCookie)?.value;
 if(!token)return NextResponse.json({error:"No autorizado."},{status:401});
 const direction=new URL(request.url).searchParams.get("direction")||"";
 const {data,error}=await authDatabase().rpc("list_directional_hr_panel",{p_token:token,p_direction:direction});
 if(error||!data?.success)return NextResponse.json({error:data?.error||error?.message||"No fue posible consultar el personal de la dirección."},{status:403});
 return NextResponse.json(data);
}
