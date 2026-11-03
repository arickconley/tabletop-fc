import * as THREE from "three";

// A separate broadcast camera leaves the player's orbit, zoom and projection intact.
export class GoalCamera {
  constructor(board) {
    this.board = board;
    this.camera = new THREE.PerspectiveCamera(55, 1, 0.1, 100);
    this.effects = new THREE.Group();
    board.scene.add(this.effects);
    this.bursts = [];
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 32;
    const ctx = canvas.getContext("2d");
    const glow = ctx.createRadialGradient(16, 16, 0, 16, 16, 16);
    glow.addColorStop(0, "#fff");
    glow.addColorStop(0.2, "#fff");
    glow.addColorStop(1, "transparent");
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, 32, 32);
    this.spark = new THREE.CanvasTexture(canvas);
  }

  start(team, ball, onEnd) {
    this.stop();
    if (this.board.reducedMotion) return false;
    this.shot = {
      team,
      side: team === "blue" ? 1 : -1,
      flank: ball.y < 3 ? -1 : 1,
      elapsed: 0,
      fired: 0,
      onEnd,
    };
    this.board.controls.enabled = false;
    this.frame(0);
    return true;
  }

  get active() {
    return !!this.shot;
  }
  get activeCamera() {
    return this.shot && this.shot.elapsed < 3.9
      ? this.camera
      : this.board.camera;
  }

  resize(width, height) {
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
  }

  burst(origin, color) {
    const count = 90;
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute(
      "position",
      new THREE.BufferAttribute(new Float32Array(count * 9), 3),
    );
    const velocities = Array.from({ length: count }, () => {
      const y = Math.random() * 2 - 1;
      const angle = Math.random() * Math.PI * 2;
      const radius = Math.sqrt(1 - y * y);
      return new THREE.Vector3(
        radius * Math.cos(angle),
        y,
        radius * Math.sin(angle),
      ).multiplyScalar(1 + Math.random() * 1.4);
    });
    const material = new THREE.PointsMaterial({
      color,
      size: 0.13,
      map: this.spark,
      transparent: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      toneMapped: false,
    });
    const points = new THREE.Points(geometry, material);
    points.frustumCulled = false;
    this.effects.add(points);
    this.bursts.push({ points, origin, velocities, age: 0 });
  }

  frame(dt) {
    const shot = this.shot;
    if (!shot) return;
    if (this.board.reducedMotion) return this.stop();
    shot.elapsed += dt;
    if (shot.elapsed >= 4.3) return this.stop();
    const t = Math.min(1, shot.elapsed / 3.6);
    const ease = t * t * (3 - 2 * t);
    const portrait = this.camera.aspect < 1;
    this.camera.position.set(
      shot.side * (1.4 + 1.5 * ease - (portrait ? 1.3 : 0)),
      1.2 - 0.35 * ease,
      shot.flank * (3.8 - ease),
    );
    this.camera.fov = (portrait ? 66 : 56) - ease * 8;
    this.camera.lookAt(shot.side * 5.25, 1.15, 0);
    this.camera.updateProjectionMatrix();
    // Brief dips to navy cover the broadcast cuts into and out of the shot.
    const fade =
      shot.elapsed < 0.25
        ? 1 - shot.elapsed / 0.25
        : shot.elapsed > 3.65
          ? Math.max(
              0,
              1 -
                Math.abs(shot.elapsed - 3.9) /
                  (shot.elapsed < 3.9 ? 0.25 : 0.4),
            )
          : 0;
    document
      .getElementById("goal-celebration")
      .style.setProperty("--cut-opacity", fade);
    const times = [0.35, 0.8, 1.35, 1.9, 2.45];
    while (shot.fired < times.length && shot.elapsed >= times[shot.fired]) {
      const i = shot.fired++;
      this.burst(
        new THREE.Vector3(
          shot.side * (5.8 + (i % 2) * 0.3),
          2.2 + (i % 3) * 0.5,
          (i % 2 ? -1 : 1) * 1.45,
        ),
        i % 2 ? 0xe6ff85 : shot.team === "blue" ? 0x55bfff : 0xff647e,
      );
    }
    for (const burst of [...this.bursts]) {
      burst.age += dt;
      if (burst.age > 1.6) {
        this.disposeBurst(burst);
        continue;
      }
      const position = burst.points.geometry.attributes.position;
      burst.velocities.forEach((v, i) => {
        for (let trail = 0; trail < 3; trail++) {
          const age = Math.max(0, burst.age - trail * 0.035);
          const travel = (1 - Math.exp(-age * 1.1)) / 1.1;
          position.setXYZ(
            i * 3 + trail,
            burst.origin.x + v.x * travel,
            burst.origin.y + v.y * travel - 0.65 * age * age,
            burst.origin.z + v.z * travel,
          );
        }
      });
      position.needsUpdate = true;
      burst.points.material.opacity = Math.max(0, 1 - burst.age / 1.6);
    }
  }

  disposeBurst(burst) {
    this.effects.remove(burst.points);
    burst.points.geometry.dispose();
    burst.points.material.dispose();
    this.bursts.splice(this.bursts.indexOf(burst), 1);
  }

  stop() {
    const shot = this.shot;
    this.shot = null;
    for (const burst of [...this.bursts]) this.disposeBurst(burst);
    if (!shot) return;
    this.board.controls.enabled = !this.board.presentation;
    shot.onEnd();
  }
}
