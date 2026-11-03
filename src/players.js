import * as THREE from "three";

const kits = { blue: 0x2789eb, red: 0xee4964 };
const skins = [0xc98255, 0xf1bd8e, 0x75442e, 0xe0a075, 0xa96843];
const hairs = [0x251c22, 0x63361e, 0x201b22, 0x30212a, 0xe9b447];
const clamp = THREE.MathUtils.clamp;

function roundedBox(w, h, d, radius) {
  const geometry = new THREE.BoxGeometry(w, h, d, 6, 6, 6);
  const positions = geometry.attributes.position;
  const inner = new THREE.Vector3(
    w / 2 - radius,
    h / 2 - radius,
    d / 2 - radius,
  );
  const point = new THREE.Vector3(),
    center = new THREE.Vector3();
  for (let i = 0; i < positions.count; i++) {
    point.fromBufferAttribute(positions, i);
    center.set(
      clamp(point.x, -inner.x, inner.x),
      clamp(point.y, -inner.y, inner.y),
      clamp(point.z, -inner.z, inner.z),
    );
    point.sub(center).normalize().multiplyScalar(radius).add(center);
    positions.setXYZ(i, point.x, point.y, point.z);
  }
  geometry.computeVertexNormals();
  return geometry;
}

function faceTexture(index) {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 256;
  const c = canvas.getContext("2d");
  const ellipse = (x, y, rx, ry, color) => {
    c.fillStyle = color;
    c.beginPath();
    c.ellipse(x, y, rx, ry, 0, 0, Math.PI * 2);
    c.fill();
  };
  for (const side of [-1, 1]) {
    const x = 128 + side * 57;
    ellipse(x, 111, 30, 32, "#fff9e9");
    ellipse(x + side * 2, 113, 16, 23, index % 2 ? "#387f87" : "#754126");
    ellipse(x + side * 2, 114, 9, 18, "#121c2b");
    ellipse(x - 5, 103, 5, 7, "#ffffff");
    c.strokeStyle = "#39252a";
    c.lineWidth = 12;
    c.lineCap = "round";
    c.beginPath();
    c.moveTo(x - 25, 65 + side * 4);
    c.quadraticCurveTo(x, 53 - index * 2, x + 25, 65 - side * 4);
    c.stroke();
  }
  // A wide little smile reads clearly in the field-level camera.
  c.fillStyle = "#733f36";
  c.beginPath();
  c.moveTo(95, 190);
  c.quadraticCurveTo(128, 205, 161, 190);
  c.quadraticCurveTo(128, 239, 95, 190);
  c.fill();
  c.fillStyle = "#fff9e9";
  c.beginPath();
  c.moveTo(101, 194);
  c.quadraticCurveTo(128, 203, 155, 194);
  c.lineTo(150, 205);
  c.quadraticCurveTo(128, 211, 106, 205);
  c.fill();
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

// Original miniature footballers, built locally from rounded, low-poly forms.
export function makeFootballer(p, textTexture) {
  const root = new THREE.Group();
  root.name = `footballer-${p.id}`;
  const index = Number(p.id.split("-")[1]) || 0;
  const look = (index + (p.team === "red" ? 2 : 0)) % 5;
  const mat = (color) =>
    new THREE.MeshStandardMaterial({ color, roughness: 0.8 });
  const skin = mat(skins[look]),
    hair = mat(hairs[look]);
  const kit = mat(
    p.keeper ? (p.team === "blue" ? 0xffc943 : 0x38d5ba) : kits[p.team],
  );
  const trim = mat(kits[p.team]),
    white = mat(0xfff6df),
    navy = mat(0x132540);
  const boot = mat(index % 2 ? 0xe4ff64 : 0xf4f5ff);
  const rig = new THREE.Group();
  rig.scale.setScalar(0.86);
  root.add(rig);
  const mesh = (geometry, material, x, y, z, parent = rig) => {
    const m = new THREE.Mesh(geometry, material);
    m.position.set(x, y, z);
    m.castShadow = true;
    m.receiveShadow = true;
    parent.add(m);
    return m;
  };
  const box = (w, h, d, radius, material, x, y, z, parent = rig) =>
    mesh(roundedBox(w, h, d, radius), material, x, y, z, parent);
  const oval = (w, h, d, material, x, y, z, parent = rig) => {
    const m = mesh(
      new THREE.SphereGeometry(1, 16, 12),
      material,
      x,
      y,
      z,
      parent,
    );
    m.scale.set(w, h, d);
    return m;
  };
  // A thin team marker remains readable from above, including for keepers.
  const marker = mesh(
    new THREE.RingGeometry(0.28, 0.33, 32),
    new THREE.MeshBasicMaterial({
      color: kits[p.team],
      side: THREE.DoubleSide,
    }),
    0,
    0.008,
    0,
    root,
  );
  marker.rotation.x = -Math.PI / 2;
  marker.castShadow = marker.receiveShadow = false;
  box(0.36, 0.36, 0.26, 0.065, kit, 0, 0.64, 0);
  box(0.34, 0.17, 0.25, 0.035, navy, 0, 0.415, 0);
  box(0.34, 0.035, 0.26, 0.012, white, 0, 0.488, 0);
  mesh(new THREE.CylinderGeometry(0.085, 0.1, 0.05, 16), skin, 0, 0.83, 0);
  mesh(
    new THREE.TorusGeometry(0.105, 0.022, 6, 20),
    white,
    0,
    0.8,
    0,
  ).rotation.x = Math.PI / 2;
  for (const x of [-0.125, 0.125])
    box(0.035, 0.26, 0.012, 0.004, white, x, 0.64, 0.132);
  const number = p.keeper ? "K" : String(index);
  const numberMaterial = new THREE.MeshBasicMaterial({
    map: textTexture(number, 0xffffff),
    transparent: true,
    depthWrite: false,
  });
  mesh(new THREE.PlaneGeometry(0.18, 0.18), numberMaterial, 0, 0.64, 0.135);
  mesh(
    new THREE.PlaneGeometry(0.23, 0.23),
    numberMaterial,
    0,
    0.64,
    -0.135,
  ).rotation.y = Math.PI;

  const arms = [],
    legs = [];
  for (const side of [-1, 1]) {
    const arm = new THREE.Group();
    arm.position.set(side * 0.235, 0.75, 0);
    rig.add(arm);
    oval(0.095, 0.12, 0.1, kit, 0, -0.065, 0, arm);
    mesh(
      new THREE.CapsuleGeometry(0.061, 0.13, 4, 10),
      p.keeper ? kit : skin,
      0,
      -0.2,
      0.015,
      arm,
    );
    box(
      p.keeper ? 0.15 : 0.115,
      p.keeper ? 0.145 : 0.12,
      0.12,
      0.04,
      p.keeper ? white : skin,
      0,
      -0.31,
      0.04,
      arm,
    );
    if (p.keeper) box(0.14, 0.04, 0.125, 0.01, trim, 0, -0.26, 0.04, arm);
    arms.push(arm);
    const leg = new THREE.Group();
    leg.position.set(side * 0.105, 0.4, 0);
    rig.add(leg);
    mesh(new THREE.CapsuleGeometry(0.065, 0.1, 4, 10), skin, 0, -0.08, 0, leg);
    mesh(
      new THREE.CylinderGeometry(0.066, 0.06, 0.16, 12),
      white,
      0,
      -0.22,
      0,
      leg,
    );
    mesh(
      new THREE.CylinderGeometry(0.068, 0.068, 0.035, 12),
      trim,
      0,
      -0.165,
      0,
      leg,
    );
    box(0.15, 0.1, 0.25, 0.035, boot, 0, -0.315, 0.05, leg);
    box(0.15, 0.027, 0.25, 0.012, navy, 0, -0.355, 0.05, leg);
    legs.push(leg);
  }

  const head = new THREE.Group();
  head.position.set(0, 1.045, 0);
  rig.add(head);
  box(0.53, 0.55, 0.47, 0.17, skin, 0, 0, 0, head);
  oval(0.055, 0.09, 0.06, skin, -0.27, -0.015, 0, head);
  oval(0.055, 0.09, 0.06, skin, 0.27, -0.015, 0, head);
  oval(0.055, 0.06, 0.075, skin, 0, -0.045, 0.245, head);
  const face = mesh(
    new THREE.PlaneGeometry(0.43, 0.37),
    new THREE.MeshBasicMaterial({
      map: faceTexture(look),
      transparent: true,
      depthWrite: false,
    }),
    0,
    -0.025,
    0.236,
    head,
  );
  face.castShadow = face.receiveShadow = false;
  oval(0.28, 0.14, 0.25, hair, 0, 0.235, -0.025, head);
  for (const side of [-1, 1])
    oval(0.025, 0.09, 0.16, hair, side * 0.25, 0.13, -0.06, head);
  if (look === 0) {
    // Close crop with a swept fringe.
    box(0.37, 0.1, 0.15, 0.045, hair, -0.055, 0.19, 0.2, head).rotation.z =
      -0.12;
  } else if (look === 1) {
    oval(0.22, 0.11, 0.18, hair, -0.025, 0.34, 0.035, head).rotation.z = -0.18;
    oval(0.16, 0.09, 0.11, hair, -0.15, 0.25, 0.2, head);
  } else if (look === 2) {
    for (let i = 0; i < 10; i++) {
      const angle = (i * Math.PI * 2) / 10;
      mesh(
        new THREE.IcosahedronGeometry(0.115, 1),
        hair,
        Math.cos(angle) * 0.225,
        0.29 + (i % 2) * 0.025,
        Math.sin(angle) * 0.19,
        head,
      );
    }
    oval(0.19, 0.13, 0.18, hair, 0, 0.34, 0, head);
  } else if (look === 3) {
    oval(0.16, 0.15, 0.16, hair, 0, 0.28, -0.3, head);
    oval(0.11, 0.19, 0.1, hair, 0, 0.08, -0.37, head);
    mesh(
      new THREE.TorusGeometry(0.09, 0.025, 6, 16),
      white,
      0,
      0.2,
      -0.33,
      head,
    );
    box(0.42, 0.09, 0.14, 0.04, hair, 0.03, 0.21, 0.19, head).rotation.z = 0.15;
  } else {
    for (let i = 0; i < 5; i++)
      oval(
        0.085,
        0.11 + (4 - i) * 0.01,
        0.08,
        hair,
        0,
        0.32,
        0.19 - i * 0.09,
        head,
      );
  }
  const badge = new THREE.Sprite(
    new THREE.SpriteMaterial({
      map: textTexture(number, 0xffffff),
      depthTest: true,
    }),
  );
  badge.scale.set(0.28, 0.28, 1);
  badge.position.set(0, 1.43, 0);
  root.add(badge);
  rig.rotation.y = p.team === "blue" ? Math.PI / 2 : -Math.PI / 2;
  root.userData.player = {
    rig,
    head,
    arms,
    legs,
    badge,
    team: p.team,
    keeper: p.keeper,
    number,
    hairstyle: look,
    heading: rig.rotation.y,
    kick: 0,
    gait: index * 1.3,
    pose: "idle",
  };
  root.position.set(p.x - 4.5, 0.16, p.y - 2.5);
  root.userData.target = root.position.clone();
  return root;
}

export function animateFootballer(
  root,
  dt,
  {
    moving = false,
    reduced = false,
    celebrating = false,
    cinematic = false,
    ball,
    camera,
  } = {},
) {
  const p = root.userData.player;
  p.badge.visible = !cinematic;
  const blend = reduced ? 1 : 1 - Math.exp(-18 * dt);
  const heading =
    celebrating && camera && !reduced
      ? Math.atan2(camera.x - root.position.x, camera.z - root.position.z)
      : p.heading;
  const delta = Math.atan2(
    Math.sin(heading - p.rig.rotation.y),
    Math.cos(heading - p.rig.rotation.y),
  );
  p.rig.rotation.y += delta * blend;
  if (reduced) p.kick = 0;
  p.kick = Math.max(0, p.kick - dt);
  p.gait += reduced ? 0 : dt * (moving ? 22 : 2.4);
  p.pose = reduced
    ? "idle"
    : celebrating
      ? "celebrating"
      : p.kick
        ? "kicking"
        : moving
          ? "running"
          : "idle";
  const run = !reduced && moving ? Math.sin(p.gait) * 0.65 : 0;
  const cheer = !reduced && celebrating;
  p.rig.position.y = reduced
    ? 0
    : cheer
      ? Math.abs(Math.sin(p.gait * 3)) * 0.12
      : moving
        ? Math.abs(Math.sin(p.gait)) * 0.035
        : Math.sin(p.gait) * 0.006;
  p.rig.rotation.x = moving && !reduced ? 0.1 : 0;
  p.legs[0].rotation.x = run;
  p.legs[1].rotation.x = p.kick
    ? -Math.sin((p.kick / 0.34) * Math.PI) * 1.1
    : -run;
  p.arms.forEach((arm, i) => {
    arm.rotation.x = (i ? 1 : -1) * run * 0.8;
    arm.rotation.z =
      (i ? 1 : -1) *
      (cheer ? 2.45 + Math.sin(p.gait * 4) * 0.18 : p.keeper ? 0.35 : 0.16);
  });
  if (ball) {
    const angle =
      Math.atan2(ball.x - root.position.x, ball.z - root.position.z) -
      p.rig.rotation.y;
    const look = clamp(
      Math.atan2(Math.sin(angle), Math.cos(angle)),
      -0.35,
      0.35,
    );
    p.head.rotation.y += (look - p.head.rotation.y) * blend;
  }
  p.head.rotation.z = reduced ? 0 : Math.sin(p.gait * 0.7) * 0.025;
}

export function disposeFootballer(root) {
  const geometries = new Set(),
    materials = new Set(),
    textures = new Set();
  root.traverse((child) => {
    if (child.geometry) geometries.add(child.geometry);
    if (child.material) materials.add(child.material);
    if (child.material?.map) textures.add(child.material.map);
  });
  geometries.forEach((g) => g.dispose());
  materials.forEach((m) => m.dispose());
  textures.forEach((t) => t.dispose());
}
