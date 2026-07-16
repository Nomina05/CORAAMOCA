export const permissionGranted=(role,permissions,key)=>role==="Administrador"||permissions?.[key]===true;

export const paidTotal=({fixedAssetPaid=0,advancePaid=0,measurements=[]})=>
  Number(fixedAssetPaid)+Number(advancePaid)+measurements
    .filter(item=>item.status==="Pagada")
    .reduce((total,item)=>total+Number(item.amount||0),0);

export const nextMeasurementStatus=(status,action="ADVANCE")=>{
  if(action==="RETURN")return status==="Revisada"?"Cubicada":status==="Libramiento"?"Revisada":null;
  return status==="Cubicada"?"Revisada":status==="Revisada"?"Libramiento":status==="Libramiento"?"Pagada":null;
};

export const paymentWithinAppropriation=(appropriation,payments)=>Number(payments)<=Number(appropriation);
