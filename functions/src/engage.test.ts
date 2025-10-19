import { postEvent } from "./engage";

async function runTests() {
  console.log("Running basic engage tests...");
  // simple smoke test using in-memory mocks would be nicer; for now just ensure export exists
  if (!postEvent) throw new Error("postEvent not exported");
  console.log("OK: postEvent exported");
}

runTests().catch(e => { console.error(e); process.exit(1); });
