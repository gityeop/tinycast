import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import { Excalidraw, MainMenu, serializeAsJSON } from "@excalidraw/excalidraw";
import "@excalidraw/excalidraw/index.css";
import "./editor.css";
import { createCanvasAgent } from "./agent.mjs";

function notify(kind, message = "") {
  window.webkit.messageHandlers.excalidraw.postMessage({ kind, message });
}

function report(error, kind = "error") {
  console.error(error);
  const status = document.getElementById("editor-error");
  status.textContent = kind === "saveError"
    ? "작업을 저장하지 못했습니다. 파일로 내보내 주세요."
    : "편집기를 열지 못했습니다. 다시 열어 주세요.";
  status.hidden = false;
  notify(kind, String(error));
}

window.addEventListener("error", (event) => report(event.error ?? event.message));
window.addEventListener("unhandledrejection", (event) => report(event.reason));

async function start() {
  document.documentElement.dataset.theme = window.oncastAppearance;
  const database = await new Promise((resolve, reject) => {
    const request = indexedDB.open("oncast-excalidraw", 1);
    request.onupgradeneeded = () => request.result.createObjectStore("editor");
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
  });

  function read(key) {
    return new Promise((resolve, reject) => {
      const request = database.transaction("editor").objectStore("editor").get(key);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  let pendingSave = Promise.resolve();
  function save(key, value) {
    pendingSave = new Promise((resolve, reject) => {
      const transaction = database.transaction("editor", "readwrite");
      transaction.objectStore("editor").put(value, key);
      transaction.oncomplete = resolve;
      transaction.onerror = () => reject(transaction.error);
      transaction.onabort = () => reject(transaction.error);
    });
    pendingSave.catch((error) => report(error, "saveError"));
    return pendingSave;
  }

  const agent = createCanvasAgent({ persist: (scene) => save("scene", scene) });

  const [scene, library] = await Promise.all([read("scene"), read("library")]);
  const initialData = scene === undefined ? {} : JSON.parse(scene);
  initialData.libraryItems = library;

  function Editor() {
    const [theme, setTheme] = useState(window.oncastAppearance);
    window.oncastEditor = {
      setTheme: (next) => {
        document.documentElement.dataset.theme = next;
        setTheme(next);
      },
      flush: () => pendingSave,
      agent,
    };
    return (
      <Excalidraw
        initialData={initialData}
        langCode="ko-KR"
        theme={theme}
        aiEnabled={false}
        onChange={(elements, appState, files) => {
          agent.observe(elements, appState, files);
          save("scene", serializeAsJSON(elements, appState, files, "local"));
        }}
        onLibraryChange={(items) => save("library", items)}
        excalidrawAPI={(api) => { agent.attach(api); notify("ready"); }}
        UIOptions={{ canvasActions: { toggleTheme: false, export: { saveFileToDisk: true } } }}
      >
        <MainMenu>
          <MainMenu.DefaultItems.LoadScene />
          <MainMenu.DefaultItems.SaveToActiveFile />
          <MainMenu.DefaultItems.Export />
          <MainMenu.DefaultItems.SaveAsImage />
          <MainMenu.Separator />
          <MainMenu.DefaultItems.ClearCanvas />
          <MainMenu.DefaultItems.ChangeCanvasBackground />
          <MainMenu.Separator />
          <MainMenu.DefaultItems.Help />
          <MainMenu.Item onSelect={() => window.location.reload()}>편집기 새로고침</MainMenu.Item>
          <MainMenu.Item onSelect={() => notify("copyMCPConfiguration")}>AI 에이전트 연결 설정 복사</MainMenu.Item>
        </MainMenu>
      </Excalidraw>
    );
  }

  createRoot(document.getElementById("root")).render(<Editor />);
}

start().catch(report);
