if (import.meta.env.PROD) {
  const status = document.getElementById("offline-status");
  if ("serviceWorker" in navigator && window.isSecureContext) {
    status.textContent = "Downloading the game for offline play…";
    navigator.serviceWorker.register("./sw.js", { updateViaCache: "none" })
      .then(async (registration) => {
        const showStatus = () => {
          if (registration.waiting) {
            status.textContent = "Update downloaded. Close all Tabletop FC windows and reopen to update. Your saved match will be kept.";
          } else if (registration.active) {
            status.textContent = "Ready to play offline on this device.";
          }
        };
        const watchInstall = () => {
          const worker = registration.installing;
          worker?.addEventListener("statechange", () => {
            if (worker.state === "redundant" && !registration.active) {
              status.textContent = "Offline download failed. Reopen the game while connected to try again.";
            } else showStatus();
          });
        };
        registration.addEventListener("updatefound", watchInstall);
        watchInstall();
        showStatus();
        await navigator.serviceWorker.ready;
        showStatus();
      })
      .catch(() => {
        status.textContent = "Offline play is unavailable. Reopen the game while connected to try again.";
      });
  } else {
    status.textContent = "Offline play needs a supported browser and a secure (HTTPS) connection.";
  }
}
