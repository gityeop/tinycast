import { hostCall } from "../host.js";

export async function withSystemDialog(operation) {
  await hostCall("window", "beginSystemDialog", []);
  try {
    return await operation();
  } finally {
    await hostCall("window", "endSystemDialog", []);
  }
}
