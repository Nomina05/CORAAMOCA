import test from "node:test";
import assert from "node:assert/strict";
import {monthlyIsr2026,payrollContribution} from "../app/lib/business-rules.mjs";
test("los aportes respetan tasas y topes 2026",()=>{
 assert.equal(payrollContribution(500000,0.0304,232230),7059.79);
 assert.equal(payrollContribution(500000,0.0287,464460),13330);
 assert.equal(monthlyIsr2026(34685,0),0);
 assert.equal(monthlyIsr2026(50000,2870),1866.75);
});
