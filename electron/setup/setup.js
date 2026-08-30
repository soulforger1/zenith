const form = document.getElementById("setup-form");
const submitButton = document.getElementById("submit");
const errorEl = document.getElementById("error");

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  errorEl.style.display = "none";
  submitButton.disabled = true;
  submitButton.textContent = "Connecting…";

  const databaseUrl = document.getElementById("database-url").value;
  const githubToken = document.getElementById("github-token").value;

  const result = await window.setupAPI.submit({ databaseUrl, githubToken });

  if (!result.ok) {
    errorEl.textContent = result.error;
    errorEl.style.display = "block";
    submitButton.disabled = false;
    submitButton.textContent = "Connect";
    return;
  }
  // On success the main process closes this window itself.
  submitButton.textContent = "Connected";
});
