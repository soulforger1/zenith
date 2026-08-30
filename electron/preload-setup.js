const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("setupAPI", {
  submit: (payload) => ipcRenderer.invoke("setup:submit", payload),
});
