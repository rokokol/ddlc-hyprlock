// Jittering RGB split with occasional row shifts — what the screen does when she glitches
//
// A complete Hyprland screen shader, not a body: decoration:screen_shader is handed this file
// as is. Same effect as the one in rokokol/hyprland-screen-shader, kept here so that flashing
// the screen needs no dependency — that repository is the one that can compose effects and
// restore what was on the screen before, this file is the standalone version of one of them
#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;
out vec4 fragColor;

float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

void main() {
    float t = time;
    // Horizontal shift by row bands, triggers rarely
    float band = floor(v_texcoord.y * 40.0);
    float jitter = (hash(band + floor(t * 12.0)) - 0.5) * 0.03;
    jitter *= step(0.92, hash(floor(t * 8.0) + band));
    vec2 suv = vec2(v_texcoord.x + jitter, v_texcoord.y);
    // RGB split that pulses over time
    float amt = 0.004 + 0.003 * sin(t * 6.0);
    float r = texture(tex, suv + vec2(amt, 0.0)).r;
    float g = texture(tex, suv).g;
    float b = texture(tex, suv - vec2(amt, 0.0)).b;
    fragColor = vec4(r, g, b, texture(tex, v_texcoord).a);
}
