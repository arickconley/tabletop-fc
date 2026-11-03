import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { legalTargets } from "./game.js";

const colors = { blue: 0x418dd2, red: 0xdf6654 };
export class Board {
  constructor(container, onCell) {
    this.container = container;
    this.onCell = onCell;
    this.pawns = new Map();
    this.targets = [];
    this.pickables = [];
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0xe9ede3);
    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.05;
    container.prepend(this.renderer.domElement);
    this.camera = new THREE.OrthographicCamera(-8, 8, 6, -6, 0.1, 100);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.enablePan = false;
    this.controls.minZoom = 0.65;
    this.controls.maxZoom = 2.1;
    this.controls.maxPolarAngle = Math.PI * 0.44;
    this.controls.minPolarAngle = 0.01;
    this.controls.target.set(0, 0, 0);
    this.scene.add(new THREE.HemisphereLight(0xffffff, 0x6f8165, 2));
    const sun = new THREE.DirectionalLight(0xfff9e9, 2.3);
    sun.position.set(-4, 12, 5);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.camera.left = -9;
    sun.shadow.camera.right = 9;
    sun.shadow.camera.top = 8;
    sun.shadow.camera.bottom = -8;
    sun.shadow.normalBias = 0.035;
    sun.shadow.bias = -0.0001;
    sun.shadow.radius = 4;
    this.scene.add(sun);
    this.makePitch();
    this.makeBall();
    this.highlightGroup = new THREE.Group();
    this.scene.add(this.highlightGroup);
    this.trailGroup = new THREE.Group();
    this.scene.add(this.trailGroup);
    this.raycaster = new THREE.Raycaster();
    this.pointer = new THREE.Vector2();
    let down = null;
    this.renderer.domElement.addEventListener("pointerdown", (e) => {
      if (e.button === 0) down = { x: e.clientX, y: e.clientY };
    });
    this.renderer.domElement.addEventListener("pointerup", (e) => {
      if (down && Math.hypot(down.x - e.clientX, down.y - e.clientY) < 6) {
        const hit = this.hit(e);
        if (hit) this.onCell(hit.x, hit.y);
      }
      down = null;
    });
    this.renderer.domElement.addEventListener("pointermove", (e) => {
      this.renderer.domElement.style.cursor = this.hit(e) ? "pointer" : "grab";
    });
    this.renderer.domElement.addEventListener("pointercancel", () => {
      down = null;
    });
    this.observer = new ResizeObserver(() => this.resize());
    this.observer.observe(container);
    this.observer.observe(document.getElementById("turn-dock"));
    this.observer.observe(document.getElementById("hud-header"));
    this.setView("perspective");
    this.resize();
    this.reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.lastTime = performance.now();
    this.renderer.setAnimationLoop((t) => this.animate(t));
  }
  material(color, extra = {}) {
    return new THREE.MeshStandardMaterial({
      color,
      roughness: 0.77,
      metalness: 0,
      ...extra,
    });
  }
  box(w, h, d, color, x, y, z, parent = this.scene) {
    const m = new THREE.Mesh(
      new THREE.BoxGeometry(w, h, d),
      this.material(color),
    );
    m.position.set(x, y, z);
    m.castShadow = true;
    m.receiveShadow = true;
    parent.add(m);
    return m;
  }
  makePitch() {
    const floor = new THREE.Mesh(
      new THREE.PlaneGeometry(200, 200),
      new THREE.ShadowMaterial({ color: 0x304735, opacity: 0.16 }),
    );
    floor.rotation.x = -Math.PI / 2;
    floor.position.y = -0.55;
    floor.receiveShadow = true;
    this.scene.add(floor);
    this.box(11.1, 0.36, 7.07, 0x193c2d, 0, -0.26, 0);
    this.box(11.04, 0.12, 7.02, 0x66855a, 0, -0.04, 0);
    this.box(10.8, 0.09, 6.8, 0x2b694a, 0, 0.045, 0);
    for (let y = 0; y < 6; y++)
      for (let x = 0; x < 10; x++) {
        this.box(
          0.987,
          0.055,
          0.987,
          (x + y) % 2 ? 0x4b985d : 0x35784a,
          x - 4.5,
          0.115,
          y - 2.5,
        );
        this.addPick(x, y);
      }
    // Fine printed grid, perimeter, halfway seam, and painted markings.
    for (let x = 0; x <= 10; x++)
      this.line(
        [
          [x - 5, 0.15, -3],
          [x - 5, 0.15, 3],
        ],
        0xc7d9b6,
        0.58,
      );
    for (let y = 0; y <= 6; y++)
      this.line(
        [
          [-5, 0.15, y - 3],
          [5, 0.15, y - 3],
        ],
        0xc7d9b6,
        0.58,
      );
    this.outline(-5, -3, 5, 3, 0xf1f1d7, 0.025);
    this.box(0.023, 0.009, 6, 0xe9edcf, 0, 0.153, 0);
    this.ring(0, 0, 1.04, 0.023, 0xf1f1d7, 0.162);
    this.ring(0, 0, 0.075, 0.013, 0xf1f1d7, 0.163);
    this.outline(-5, -1, -3, 1, 0xe3e8ca, 0.022);
    this.outline(3, -1, 5, 1, 0xe3e8ca, 0.022);
    for (const x of [-5, 5]) this.goal(x);
    for (let x = 0; x < 10; x++)
      this.flatText(String(x + 1), x - 4.5, -3.22, 0.18, 0.24, 0xc1d3b6);
    for (let y = 0; y < 6; y++)
      this.flatText(
        String.fromCharCode(65 + y),
        -5.23,
        y - 2.5,
        0.18,
        0.22,
        0xc1d3b6,
      );
    this.flatText("GRIDKICK  /  60", 0, 3.29, 2.4, 0.19, 0xe3e6ca);
    this.flatText("BLUE  →", -3.9, 3.28, 1.1, 0.18, 0xa4c7e9);
    this.flatText("←  RED", 3.9, 3.28, 1.1, 0.18, 0xeeb1a1);
    this.box(0.018, 0.03, 7.04, 0x234f37, 0, -0.005, 0);
  }
  addPick(x, y) {
    const m = new THREE.Mesh(
      new THREE.PlaneGeometry(1, 1),
      new THREE.MeshBasicMaterial({ visible: false, side: THREE.DoubleSide }),
    );
    m.rotation.x = -Math.PI / 2;
    m.position.set(x - 4.5, 0.185, y - 2.5);
    m.userData = { x, y };
    this.scene.add(m);
    this.pickables.push(m);
  }
  line(points, color, opacity = 1, parent = this.scene) {
    const m = new THREE.Line(
      new THREE.BufferGeometry().setFromPoints(
        points.map((p) => new THREE.Vector3(...p)),
      ),
      new THREE.LineBasicMaterial({ color, transparent: opacity < 1, opacity }),
    );
    parent.add(m);
    return m;
  }
  outline(x1, z1, x2, z2, color, width) {
    this.box(x2 - x1, 0.008, width, color, (x1 + x2) / 2, 0.155, z1);
    this.box(x2 - x1, 0.008, width, color, (x1 + x2) / 2, 0.155, z2);
    this.box(width, 0.008, z2 - z1, color, x1, 0.155, (z1 + z2) / 2);
    this.box(width, 0.008, z2 - z1, color, x2, 0.155, (z1 + z2) / 2);
  }
  ring(x, z, r, width, color, y = 0.17, parent = this.scene) {
    const mesh = new THREE.Mesh(
      new THREE.RingGeometry(r - width, r, 64),
      new THREE.MeshBasicMaterial({ color, side: THREE.DoubleSide }),
    );
    mesh.rotation.x = -Math.PI / 2;
    mesh.position.set(x, y, z);
    parent.add(mesh);
    return mesh;
  }
  textTexture(text, color) {
    const canvas = document.createElement("canvas");
    canvas.width = text.length <= 2 ? 128 : 512;
    canvas.height = 128;
    const c = canvas.getContext("2d");
    c.fillStyle = `#${new THREE.Color(color).getHexString()}`;
    c.font = "bold 64px Arial";
    if (c.measureText(text).width > canvas.width - 20)
      c.font = `bold ${(64 * (canvas.width - 20)) / c.measureText(text).width}px Arial`;
    c.textAlign = "center";
    c.textBaseline = "middle";
    c.fillText(text, canvas.width / 2, 64);
    const t = new THREE.CanvasTexture(canvas);
    t.colorSpace = THREE.SRGBColorSpace;
    return t;
  }
  flatText(text, x, z, w, h, color) {
    const mesh = new THREE.Mesh(
      new THREE.PlaneGeometry(w, h),
      new THREE.MeshBasicMaterial({
        map: this.textTexture(text, color),
        transparent: true,
        depthWrite: false,
      }),
    );
    mesh.rotation.x = -Math.PI / 2;
    mesh.position.set(x, 0.18, z);
    this.scene.add(mesh);
  }
  goal(x) {
    const side = Math.sign(x),
      back = x + side * 0.68;
    this.box(0.75, 0.12, 2.16, 0x456c4e, x + side * 0.35, 0.06, 0);
    for (const z of [-1, 1]) {
      this.box(0.055, 0.95, 0.055, 0xf0efda, x, 0.6, z);
      this.box(0.055, 0.83, 0.055, 0xe0e4cc, back, 0.55, z);
      this.box(0.72, 0.045, 0.045, 0xf0efda, x + side * 0.34, 1.06, z);
    }
    this.box(0.055, 0.055, 2.06, 0xfffce8, x, 1.07, 0);
    this.box(0.055, 0.045, 2.06, 0xe0e4cc, back, 0.96, 0);
    for (let z = -1; z <= 1.01; z += 0.17) {
      this.line(
        [
          [back, 0.15, z],
          [back, 0.97, z],
          [x, 1.06, z],
        ],
        0xe8ecd6,
        0.7,
      );
    }
    for (let h = 0.17; h < 1; h += 0.16) {
      this.line(
        [
          [x, h, -1],
          [back, h, -1],
          [back, h, 1],
          [x, h, 1],
        ],
        0xe8ecd6,
        0.7,
      );
    }
    for (const y of [2, 3]) this.addPick(x < 0 ? -1 : 10, y);
  }
  makePawn(p) {
    const group = new THREE.Group(),
      body = this.material(colors[p.team]),
      rim = this.material(p.team === "blue" ? 0x2863a0 : 0xb74534),
      white = this.material(0xfff9e5);
    const part = (geometry, mat, y) => {
      const m = new THREE.Mesh(geometry, mat);
      m.position.y = y;
      m.castShadow = true;
      m.receiveShadow = true;
      group.add(m);
      return m;
    };
    part(new THREE.CylinderGeometry(0.29, 0.32, 0.13, 40), rim, 0.08);
    part(new THREE.CylinderGeometry(0.25, 0.28, 0.09, 40), body, 0.18);
    part(new THREE.CylinderGeometry(0.145, 0.22, 0.32, 32), body, 0.37);
    part(new THREE.SphereGeometry(0.183, 32, 20), body, 0.72);
    part(new THREE.CylinderGeometry(0.19, 0.13, 0.12, 32), body, 0.56);
    if (p.keeper)
      part(new THREE.CylinderGeometry(0.19, 0.19, 0.06, 32), white, 0.75);
    for (let i = 0; i < 4; i++) {
      const layer = new THREE.Mesh(
        new THREE.TorusGeometry(0.285 - i * 0.008, 0.003, 4, 40),
        rim,
      );
      layer.rotation.x = Math.PI / 2;
      layer.position.y = 0.12 + i * 0.018;
      group.add(layer);
    }
    const label = new THREE.Sprite(
      new THREE.SpriteMaterial({
        map: this.textTexture(p.keeper ? "K" : p.id.split("-")[1], 0xffffff),
        depthTest: true,
      }),
    );
    label.scale.set(0.32, 0.32, 1);
    label.position.set(0, 0.98, 0);
    group.add(label);
    group.position.set(p.x - 4.5, 0.16, p.y - 2.5);
    group.userData.target = group.position.clone();
    this.scene.add(group);
    return group;
  }
  makeBall() {
    this.ball = new THREE.Group();
    const sphere = new THREE.Mesh(
      new THREE.SphereGeometry(0.2, 32, 24),
      this.material(0xfffdf1, { roughness: 0.55 }),
    );
    sphere.castShadow = true;
    this.ball.add(sphere);
    const ico = new THREE.IcosahedronGeometry(1, 0),
      positions = ico.getAttribute("position"),
      seen = new Set();
    for (let i = 0; i < positions.count; i++) {
      const n = new THREE.Vector3()
          .fromBufferAttribute(positions, i)
          .normalize(),
        key = n
          .toArray()
          .map((v) => v.toFixed(3))
          .join(",");
      if (seen.has(key)) continue;
      seen.add(key);
      const u = new THREE.Vector3(0, 1, 0).cross(n).normalize(),
        v = n.clone().cross(u),
        verts = [];
      const center = n.clone().multiplyScalar(0.211);
      for (let j = 0; j < 5; j++) {
        const point = (k) =>
          n
            .clone()
            .multiplyScalar(0.202)
            .addScaledVector(u, Math.cos((k * Math.PI * 2) / 5) * 0.083)
            .addScaledVector(v, Math.sin((k * Math.PI * 2) / 5) * 0.083)
            .normalize()
            .multiplyScalar(0.213);
        verts.push(
          ...center.toArray(),
          ...point(j).toArray(),
          ...point(j + 1).toArray(),
        );
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute("position", new THREE.Float32BufferAttribute(verts, 3));
      g.computeVertexNormals();
      this.ball.add(
        new THREE.Mesh(g, this.material(0x24362b, { side: THREE.DoubleSide })),
      );
    }
    ico.dispose();
    this.ball.position.set(0, 0.4, 0);
    this.ballTarget = this.ball.position.clone();
    this.scene.add(this.ball);
    this.ballRing = this.ring(0, 0, 0.34, 0.018, 0xfff4c6, 0.17);
  }
  clearGroup(group) {
    while (group.children.length) {
      const c = group.children[0];
      group.remove(c);
      c.geometry?.dispose();
      if (c.material?.map) c.material.map.dispose();
      c.material?.dispose();
    }
  }
  update(s) {
    for (const [id, mesh] of this.pawns) {
      if (!s.pawns.some((p) => p.id === id)) {
        this.scene.remove(mesh);
        mesh.traverse((c) => {
          c.geometry?.dispose();
          c.material?.map?.dispose();
          c.material?.dispose();
        });
        this.pawns.delete(id);
      }
    }
    for (const p of s.pawns) {
      if (!this.pawns.has(p.id)) this.pawns.set(p.id, this.makePawn(p));
      const mesh = this.pawns.get(p.id);
      mesh.userData.cell = { x: p.x, y: p.y };
      mesh.userData.target.set(p.x - 4.5, 0.16, p.y - 2.5);
    }
    const carrier = s.pawns.some((p) => p.x === s.ball.x && p.y === s.ball.y);
    this.ballTarget.set(s.ball.x - 4.5, carrier ? 1.35 : 0.38, s.ball.y - 2.5);
    this.ball.userData.cell = { ...s.ball };
    this.ball.visible = s.phase !== "placement";
    this.ballRing.visible = this.ball.visible;
    this.clearGroup(this.highlightGroup);
    this.clearGroup(this.trailGroup);
    this.targets = legalTargets(s);
    for (const t of this.targets) {
      const geometry = new THREE.PlaneGeometry(0.83, 0.83);
      const mesh = new THREE.Mesh(
        geometry,
        new THREE.MeshBasicMaterial({
          color: t.goal ? 0xffffff : 0xf5d16f,
          transparent: true,
          opacity: 0.35,
          depthWrite: false,
        }),
      );
      mesh.rotation.x = -Math.PI / 2;
      mesh.position.set(t.x - 4.5, 0.18, t.y - 2.5);
      this.highlightGroup.add(mesh);
      this.ring(
        t.x - 4.5,
        t.y - 2.5,
        0.105,
        0.04,
        t.pass ? 0xffffff : 0xfbe59d,
        0.19,
        this.highlightGroup,
      );
    }
    const selected = s.pawns.find((p) => p.id === (s.relocating || s.selected));
    if (selected)
      this.ring(
        selected.x - 4.5,
        selected.y - 2.5,
        0.39,
        0.042,
        0xffd16a,
        0.19,
        this.highlightGroup,
      );
    if (s.phase === "select")
      for (const p of s.pawns.filter((p) => p.team === s.team))
        this.ring(
          p.x - 4.5,
          p.y - 2.5,
          0.39,
          0.022,
          0xf0ce7a,
          0.19,
          this.highlightGroup,
        );
    for (const p of s.trail) {
      this.ring(
        p.x - 4.5,
        p.y - 2.5,
        0.07,
        0.055,
        p.kind === "run" ? 0xf4c973 : 0xf8f5df,
        0.19,
        this.trailGroup,
      );
    }
  }
  hit(event) {
    // Pointer input can arrive before the next animation frame after a placement.
    this.scene.updateMatrixWorld(true);
    this.camera.updateMatrixWorld(true);
    const rect = this.renderer.domElement.getBoundingClientRect();
    this.pointer.set(
      ((event.clientX - rect.left) / rect.width) * 2 - 1,
      (-(event.clientY - rect.top) / rect.height) * 2 + 1,
    );
    this.raycaster.setFromCamera(this.pointer, this.camera);
    const pieces = [
      ...this.pawns.values(),
      ...(this.ball.visible ? [this.ball] : []),
    ];
    const hit = this.raycaster.intersectObjects(pieces, true)[0];
    const groundCell = this.raycaster.intersectObjects(this.pickables)[0]
      ?.object.userData;
    let pieceCell;
    if (hit) {
      let object = hit.object;
      while (object) {
        if (object.userData.cell) {
          pieceCell = object.userData.cell;
          break;
        }
        object = object.parent;
      }
    }
    const isTarget = (cell) =>
      cell && this.targets.some((t) => t.x === cell.x && t.y === cell.y);
    // A tall pawn can overlap a neighboring square in perspective. Keep that
    // highlighted square clickable, while still accepting direct receiver clicks.
    if (isTarget(pieceCell)) return pieceCell;
    if (isTarget(groundCell)) return groundCell;
    return pieceCell || groundCell;
  }
  resize() {
    const viewport = this.container.getBoundingClientRect();
    const { width, height } = viewport;
    if (!width || !height) return;
    // Fit the tabletop into the clear space between the HUD and command dock.
    // The WebGL canvas itself always fills the entire window.
    const header = document
      .getElementById("hud-header")
      .getBoundingClientRect();
    const dock = document.getElementById("turn-dock").getBoundingClientRect();
    const top = Math.max(0, header.bottom - viewport.top) + 12;
    const bottom = Math.max(0, viewport.bottom - dock.top) + 12;
    const usableHeight = Math.max(80, height - top - bottom);
    const usableWidth = Math.max(120, width - 36);
    this.camera.updateMatrixWorld(true);
    const bounds = new THREE.Box3();
    for (const x of [-5.9, 5.9])
      for (const y of [-0.55, 1.6])
        for (const z of [-3.6, 3.6])
          bounds.expandByPoint(
            new THREE.Vector3(x, y, z).applyMatrix4(
              this.camera.matrixWorldInverse,
            ),
          );
    const size = bounds.getSize(new THREE.Vector3());
    const center = bounds.getCenter(new THREE.Vector3());
    const half =
      Math.max(
        (size.y * height) / usableHeight,
        (size.x * height) / usableWidth,
      ) * 0.53;
    const aspect = width / height;
    const offset = (half * (top - bottom)) / height;
    this.camera.left = center.x - half * aspect;
    this.camera.right = center.x + half * aspect;
    this.camera.top = center.y + half + offset;
    this.camera.bottom = center.y - half + offset;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(width, height);
  }
  setView(view) {
    this.camera.position.set(
      view === "top" ? 0 : 1.7,
      view === "top" ? 18 : 12,
      view === "top" ? 0.001 : 11,
    );
    this.camera.zoom = 1;
    this.controls.target.set(0, 0, 0);
    this.camera.lookAt(0, 0, 0);
    this.camera.updateProjectionMatrix();
    this.controls.update();
    this.resize();
  }
  animate(t) {
    const dt = Math.min((t - this.lastTime) / 1000, 0.1);
    this.lastTime = t;
    const blend = this.reducedMotion ? 1 : 1 - Math.exp(-14 * dt);
    for (const mesh of this.pawns.values())
      mesh.position.lerp(mesh.userData.target, blend);
    const moving = this.ball.position.distanceTo(this.ballTarget);
    this.ball.position.lerp(this.ballTarget, blend);
    if (moving > 0.02) {
      this.ball.rotation.z += dt * 3;
      this.ball.rotation.x += dt * 2;
    }
    this.ballRing.position.set(
      this.ball.position.x,
      0.17,
      this.ball.position.z,
    );
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }
  // Exposes coordinates for browser interaction tests, without bypassing input handling.
  screenPosition(x, y) {
    const p = new THREE.Vector3(x - 4.5, 0.185, y - 2.5).project(this.camera),
      r = this.renderer.domElement.getBoundingClientRect();
    return {
      x: r.left + ((p.x + 1) * r.width) / 2,
      y: r.top + ((1 - p.y) * r.height) / 2,
    };
  }
}
