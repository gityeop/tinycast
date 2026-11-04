import { z } from "zod";
import {
  CaptureUpdateAction, convertToExcalidrawElements, exportToBlob, newElementWith, serializeAsJSON,
} from "@excalidraw/excalidraw";

const number = z.number().finite();
const id = z.string().min(1);
const point = z.tuple([number, number]);
const style = {
  x: number.optional(), y: number.optional(), width: number.nonnegative().optional(),
  height: number.nonnegative().optional(), angle: number.optional(),
  strokeColor: z.string().optional(), backgroundColor: z.string().optional(),
  fillStyle: z.enum(["hachure", "cross-hatch", "solid", "zigzag"]).optional(),
  strokeStyle: z.enum(["solid", "dashed", "dotted"]).optional(), strokeWidth: number.nonnegative().optional(),
  roughness: number.nonnegative().optional(), opacity: number.min(0).max(100).optional(),
  text: z.string().optional(), fontSize: number.positive().optional(), fontFamily: z.number().int().optional(),
  textAlign: z.enum(["left", "center", "right"]).optional(),
  verticalAlign: z.enum(["top", "middle", "bottom"]).optional(),
  points: z.array(point).min(2).optional(), groupIds: z.array(id).optional(),
  roundness: z.object({ type: z.number().int(), value: number.optional() }).strict().nullable().optional(),
  startArrowhead: z.enum(["arrow", "bar", "dot", "triangle", "diamond"]).nullable().optional(),
  endArrowhead: z.enum(["arrow", "bar", "dot", "triangle", "diamond"]).nullable().optional(),
};
const label = z.object({ text: z.string(), fontSize: number.positive().optional() }).strict();
const endpoint = z.object({ id, x: number.optional(), y: number.optional() }).strict();
const skeleton = z.object({
  ...style, id: id.optional(), type: z.enum(["rectangle", "ellipse", "diamond", "text", "arrow", "line"]),
  x: number, y: number, label: label.optional(), start: endpoint.optional(), end: endpoint.optional(),
}).strict();
const identity = z.object({ canvasId: id }).strict();
const mutation = z.object({
  canvasId: id, expectedRevision: z.number().int().nonnegative(),
  create: z.array(skeleton).default([]),
  update: z.array(z.object({ id, changes: z.object(style).strict() }).strict()).default([]),
  delete: z.array(id).default([]),
}).strict().refine((value) => value.create.length + value.update.length + value.delete.length > 0, "No changes supplied");

export function createCanvasAgent({ persist }) {
  const canvasId = crypto.randomUUID();
  let api;
  let signature;
  let revision = 0;
  let busy = false;

  function observe(elements, appState, files) {
    const next = JSON.stringify([elements, appState.viewBackgroundColor, files]);
    if (signature !== next) {
      if (signature !== undefined) revision += 1;
      signature = next;
    }
  }

  function current() {
    if (!api) throw new Error("The Oncast canvas is still loading");
    const elements = api.getSceneElementsIncludingDeleted();
    const appState = api.getAppState();
    if (appState.isLoading) throw new Error("The Oncast canvas is still restoring its drawing. Read it again when ready.");
    const files = api.getFiles();
    observe(elements, appState, files);
    return { elements, appState, files };
  }

  function read() {
    const { elements, appState, files } = current();
    return {
      canvasId, revision, elements: elements.filter((element) => !element.isDeleted),
      selectedElementIds: Object.keys(appState.selectedElementIds).filter((key) => appState.selectedElementIds[key]),
      viewport: { scrollX: appState.scrollX, scrollY: appState.scrollY, zoom: appState.zoom.value },
      viewBackgroundColor: appState.viewBackgroundColor,
      files: Object.values(files).map(({ id, mimeType }) => ({ id, mimeType })),
    };
  }

  function requireCanvas(value) {
    if (value.canvasId !== canvasId) throw new Error("Canvas changed. Read the current canvas before continuing.");
  }

  async function apply(input) {
    const args = mutation.parse(input);
    requireCanvas(args);
    const { elements, appState } = current();
    if (appState.cursorButton === "down" || appState.editingTextElement) {
      throw new Error("The user is editing the canvas. Finish that edit before applying agent changes.");
    }
    if (args.expectedRevision !== revision) {
      throw new Error(`Revision conflict: expected ${args.expectedRevision}, current ${revision}. Read the canvas again.`);
    }
    const existing = new Map(elements.filter((element) => !element.isDeleted).map((element) => [element.id, element]));
    const touched = new Set();
    for (const key of [...args.update.map((update) => update.id), ...args.delete]) {
      if (!existing.has(key)) throw new Error(`Element does not exist: ${key}`);
      if (touched.has(key)) throw new Error(`Element is targeted more than once: ${key}`);
      touched.add(key);
    }
    for (const item of args.create) {
      if (item.id && elements.some((element) => element.id === item.id)) throw new Error(`Element ID already exists: ${item.id}`);
    }
    const created = convertToExcalidrawElements(args.create, { regenerateIds: false });
    const createdIds = new Set();
    for (const element of created) {
      if (createdIds.has(element.id) || existing.has(element.id)) throw new Error(`Duplicate element ID: ${element.id}`);
      createdIds.add(element.id);
    }
    const updates = new Map(args.update.map((item) => [item.id, item.changes]));
    const deleted = new Set(args.delete);
    const next = elements.map((element) => {
      if (deleted.has(element.id)) return newElementWith(element, { isDeleted: true });
      const changes = updates.get(element.id);
      if (!changes) return element;
      if (changes.text !== undefined && element.type !== "text") throw new Error(`Element is not text: ${element.id}`);
      return newElementWith(element, changes.text === undefined ? changes : { ...changes, originalText: changes.text });
    }).concat(created);
    if (JSON.stringify(elements) !== JSON.stringify(next)) {
      await new Promise((resolve) => {
        const unsubscribe = api.onChange((changed, state, files) => {
          observe(changed, state, files);
          unsubscribe();
          resolve();
        });
        api.updateScene({ elements: next, captureUpdate: CaptureUpdateAction.IMMEDIATELY });
      });
      const scene = current();
      await persist(serializeAsJSON(scene.elements, scene.appState, scene.files, "local"));
      api.setToast({ message: "AI 에이전트가 캔버스를 수정했습니다." });
    }
    return { ...read(), createdElementIds: [...createdIds] };
  }

  return {
    attach: (value) => { api = value; },
    observe,
    request: async (operation, input) => {
      if (busy) throw new Error("The canvas is applying another agent edit. Read it again after that edit completes.");
      switch (operation) {
        case "read_canvas": z.object({}).strict().parse(input); return read();
        case "apply_canvas_changes":
          busy = true;
          try { return await apply(input); } finally { busy = false; }
        case "export_canvas_scene": {
          requireCanvas(identity.parse(input));
          const scene = current();
          return { canvasId, revision, scene: JSON.parse(serializeAsJSON(scene.elements, scene.appState, scene.files, "local")) };
        }
        case "snapshot_canvas": {
          requireCanvas(identity.parse(input));
          const currentScene = current();
          const scene = {
            elements: structuredClone(currentScene.elements.filter((element) => !element.isDeleted)),
            files: structuredClone(currentScene.files),
            appState: { ...currentScene.appState },
          };
          const capturedRevision = revision;
          const blob = await exportToBlob({ ...scene, mimeType: "image/png", exportPadding: 20 });
          const image = await new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result.split(",")[1]);
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(blob);
          });
          return { canvasId, revision: capturedRevision, image };
        }
        default: throw new Error(`Unknown canvas operation: ${operation}`);
      }
    },
  };
}
