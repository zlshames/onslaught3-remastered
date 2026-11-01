// The sharp ground (docs/SCREEN_FIT_PLAN.md §7.3): sand noise painted in
// world coordinates, colour-matched to the original ground, so it stays crisp
// at any zoom and screen density and runs on past the play area.
#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

// The palette, light to dark.
uniform vec4 uLight;
uniform vec4 uMid;
uniform vec4 uDark;

out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
    mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
    u.y
  );
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise(p);
    p = p * 2.03 + vec2(17.0, 9.0);
    a *= 0.5;
  }
  return v;
}

void main() {
  // The ground is drawn in world coordinates, and FlutterFragCoord is the
  // fragment's position in the canvas's local space: world px.
  vec2 w = FlutterFragCoord().xy;
  // Broad light and dark patches, a sand grain about a world px across, and
  // a finer grain that only shows when zoomed in.
  float patches = fbm(w / 110.0);
  float grain = noise(w * 0.9);
  float fine = noise(w * 3.7);
  float t = 0.5 + (patches - 0.5) * 0.9 + (grain - 0.5) * 0.35 + (fine - 0.5) * 0.15;
  // Scattered round dark specks, like the original's pitted sand: about one
  // in thirty cells of 1.6 world px holds one, at a random spot in its cell.
  vec2 cell = floor(w / 1.6);
  vec2 centre = (cell + vec2(0.2) + 0.6 * vec2(hash(cell + 3.1), hash(cell + 7.7))) * 1.6;
  float speck = step(0.966, hash(cell)) * (1.0 - smoothstep(0.25, 0.55, length(w - centre)));
  vec4 colour = t > 0.5 ? mix(uMid, uLight, (t - 0.5) * 2.0) : mix(uDark, uMid, t * 2.0);
  colour = mix(colour, uDark, speck * 0.6);
  fragColor = vec4(colour.rgb, 1.0);
}
