import { planTurn, choosePlacement } from "./ai.js";

self.onmessage = ({ data }) => {
  try {
    const plan =
      data.phase === "placement"
        ? [choosePlacement(data)].filter(Boolean)
        : planTurn(data);
    self.postMessage({ plan });
  } catch (error) {
    self.postMessage({ error: error.message });
  }
};
