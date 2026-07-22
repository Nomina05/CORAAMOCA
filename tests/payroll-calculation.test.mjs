import test from "node:test";
import assert from "node:assert/strict";
import {incrementalMonthlyIsr2026,monthlyIsr2026,payrollContribution} from "../app/lib/business-rules.mjs";
test("los aportes respetan tasas y topes 2026",()=>{
 assert.equal(payrollContribution(500000,0.0304,232230),7059.79);
 assert.equal(payrollContribution(500000,0.0287,464460),13330);
 assert.equal(monthlyIsr2026(34685,0),0);
 assert.equal(monthlyIsr2026(50000,2870),1866.75);
});

test("distribuye el ISR acumulado entre nómina fija y prima",()=>{
 const fixedTss=payrollContribution(42000,0.0287,464460)+payrollContribution(42000,0.0304,232230);
 assert.equal(monthlyIsr2026(42000,fixedTss),724.92);
 assert.equal(incrementalMonthlyIsr2026({previousGross:42000,previousEmployeeTss:fixedTss,currentGross:15000,currentEmployeeTss:0}),2374.49);
 assert.equal(incrementalMonthlyIsr2026({previousGross:57000,previousEmployeeTss:fixedTss,currentGross:5000,withhold:false}),0);
});
