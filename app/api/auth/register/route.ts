import { NextResponse } from "next/server";

export async function POST() {
  return NextResponse.json({error:"El autorregistro está deshabilitado. El administrador debe crear y vincular el usuario desde Usuarios y Roles."},{status:403});
}
