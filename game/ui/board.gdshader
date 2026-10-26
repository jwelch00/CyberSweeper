// The whole visible board in one pass. Cell states come from a 256x256
// wrap-around texture keyed by world cell (board_view.gd); glyphs from the
// atlas built by glyph_atlas.gd. Sizes follow design/shared/cs.css at 1x zoom:
// 40 px cells, 3 px gaps, hidden chips cut 16% at the top left.
shader_type canvas_item;
render_mode unshaded;

const float CELL = 40.0;
const float GAP = 3.0;
const float ATLAS_COLS = 8.0;
const float ATLAS_ROWS = 4.0;
const float GLYPH_BOX = 256.0 / 96.0;   // atlas cell side / glyph font size
const float SHAPE_BOX = 256.0 / 160.0;  // atlas cell side / flag-mine viewBox size

// cell states (red channel)
const int HIDDEN = 0;
const int OPEN = 1;
const int HIT = 2;
const int FLAG = 3;
const int MINE_SHOWN = 4;
const int WRONG_FLAG = 5;

uniform sampler2D cells : filter_nearest, repeat_enable;
uniform sampler2D glyphs : filter_linear_mipmap;
uniform sampler2D glow_s : filter_linear_mipmap;
uniform sampler2D glow_l : filter_linear_mipmap;

uniform vec2 view_size = vec2(1920.0, 1080.0);
uniform vec2 cam = vec2(0.5);
uniform float zoom = 1.0;
uniform float number_px = 20.8;   // max(11, 52% of the cell), from BoardCamera
uniform float now15 = 0.0;        // animation clock, ms mod 32768
uniform float drift_ms = 0.0;     // cipher drift clock (frozen with reduced motion)
uniform float motion = 1.0;       // 0 with reduced motion
uniform vec2 hover = vec2(1e9);
uniform vec2 chord = vec2(1e9);
uniform float hex_advance = 0.6;
uniform float digit_dy = 0.0;
uniform float hex_dy = 0.0;

uniform vec4 c_void;
uniform vec4 c_floor;
uniform vec4 c_grid;
uniform vec4 c_tile;
uniform vec4 c_edge;
uniform vec4 c_cipher;
uniform vec4 c_ink_dim;
uniform vec4 c_accent;
uniform vec4 c_accent2;
uniform vec4 c_warn;
uniform vec4 c_danger;
uniform vec4 nums[8];

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vec4 cell_data(vec2 c) {
	ivec2 t = ivec2(int(mod(c.x, 256.0)), int(mod(c.y, 256.0)));
	return texelFetch(cells, t, 0);
}

int state_of(vec4 d) { return int(d.r * 255.0 + 0.5); }
int number_of(vec4 d) { return int(d.g * 255.0 + 0.5); }

// Milliseconds since this cell's event (negative = not yet), or 1e6 if settled.
float age_of(vec4 d) {
	float hi = d.a * 255.0 + 0.5;
	if (hi < 128.0) return 1e6;
	float t = floor(d.b * 255.0 + 0.5) + floor(hi - 128.0) * 256.0;
	float a = mod(now15 - t + 32768.0, 32768.0);
	return a > 16384.0 ? a - 32768.0 : a;
}

// Alpha of atlas glyph (col, row) at uv in [0,1] of its atlas cell.
float atlas(sampler2D tex, float col, float row, vec2 uv) {
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) return 0.0;
	return texture(tex, (vec2(col, row) + uv) / vec2(ATLAS_COLS, ATLAS_ROWS)).a;
}

// uv of a point inside a glyph box of side `box` centred at `centre`.
vec2 box_uv(vec2 p, vec2 centre, float box) {
	return (p - centre) / box + 0.5;
}

// CSS cubic-bezier(x1, y1, x2, y2) at t (bisection; only used for a few cells).
float bez(float x1, float y1, float x2, float y2, float t) {
	float lo = 0.0, hi = 1.0, u = t;
	for (int i = 0; i < 14; i++) {
		u = (lo + hi) * 0.5;
		float v = 1.0 - u;
		float x = 3.0 * v * v * u * x1 + 3.0 * v * u * u * x2 + u * u * u;
		if (x < t) lo = u; else hi = u;
	}
	float v = 1.0 - u;
	return 3.0 * v * v * u * y1 + 3.0 * v * u * u * y2 + u * u * u;
}

// The mine hit as the corp's hazard tile (design/shared/cs.css .c.m.hit):
// diagonal warn/void stripes, a 1 px danger edge, a void octagon inset 18%
// holding the mine in danger with a 1 px accent2/accent split. It slams in
// (scale 1.35 -> 1, brightness 3 -> 1 over 120 ms with overshoot) and the
// stripes march for 1.2 s. q is relative to the hit cell's chip; alpha 0 =
// not on the tile.
vec4 hazard(vec2 q, float cs, float age) {
	float sc = 1.0;
	float bright = 1.0;
	bool fresh = age >= 0.0 && age < 1e5 && motion > 0.5;
	if (fresh && age < 120.0) {
		float e = bez(0.2, 1.5, 0.4, 1.0, age / 120.0);
		sc = mix(1.35, 1.0, e);
		bright = mix(3.0, 1.0, e);
	}
	vec2 mid = vec2(cs * 0.5);
	vec2 p = mid + (q - mid) / sc;
	if (p.x < 0.0 || p.y < 0.0 || p.x > cs || p.y > cs) return vec4(0.0);
	float period = 10.0 * zoom;
	float march = fresh && age < 1200.0 ? age / 600.0 : 0.0;
	float d = fract((p.x + p.y) * 0.70710678 / period + march);
	float aa = 0.8 / period;
	float on = smoothstep(0.0, aa, d) * (1.0 - smoothstep(0.5 - aa, 0.5, d));
	vec3 dark = mix(c_void.rgb, c_warn.rgb, 0.08);
	vec3 col = mix(dark, c_warn.rgb, on);
	float e = min(min(p.x, p.y), min(cs - p.x, cs - p.y));
	if (e < max(1.0, zoom)) col = c_danger.rgb;
	// void octagon, inset 18%, corners cut at 22% of its side
	vec2 o = (p - vec2(0.18 * cs)) / (0.64 * cs);
	if (o.x >= 0.0 && o.y >= 0.0 && o.x <= 1.0 && o.y <= 1.0) {
		vec2 m = min(o, 1.0 - o);
		if (m.x + m.y >= 0.22) {
			col = c_void.rgb;
			float box = 0.52 * cs * SHAPE_BOX;
			vec2 uv = box_uv(p, mid, box);
			float sh = zoom / box;
			col = mix(col, c_accent2.rgb, atlas(glyphs, 1.0, 3.0, uv + vec2(sh, 0.0)) * 0.9);
			col = mix(col, c_accent.rgb, atlas(glyphs, 1.0, 3.0, uv - vec2(sh, 0.0)) * 0.9);
			col = mix(col, c_danger.rgb, atlas(glyphs, 1.0, 3.0, uv));
			col = mix(col, c_void.rgb, atlas(glyphs, 2.0, 3.0, uv));
		}
	}
	return vec4(min(col * bright, vec3(1.0)), 1.0);
}

// Is a revealed (floor) cell within `spread` px of point lp (local to cell c)?
bool floor_near(vec2 c, vec2 lp, float cs, float pitch, vec2 off, float spread) {
	vec4 d = cell_data(c + off);
	int s = state_of(d);
	bool open = s == OPEN || s == HIT || s == MINE_SHOWN || s == WRONG_FLAG;
	if (s == OPEN && age_of(d) < 0.0) open = false;
	if (!open) return false;
	vec2 q = lp - off * pitch;        // point relative to that cell's chip
	vec2 dd = max(max(-q, q - vec2(cs)), vec2(0.0));
	return max(dd.x, dd.y) <= spread;
}

void fragment() {
	vec2 px = UV * view_size;
	float pitch = (CELL + GAP) * zoom;
	float cs = CELL * zoom;
	vec2 w = (px - view_size * 0.5) / pitch + cam;
	vec2 c = floor(w);
	vec2 lp = (w - c) * pitch;
	bool chip = lp.x < cs && lp.y < cs;
	vec4 d = cell_data(c);
	int st = state_of(d);
	int num = number_of(d);
	float age = age_of(d);
	if (st == OPEN && age < 0.0) st = HIDDEN;   // cascade hasn't reached it yet
	vec2 centre = vec2(cs * 0.5);

	vec3 col = c_void.rgb;

	// --- revealed floor, continuous across the 3 px gaps -----------------------
	bool open_here = st == OPEN || st == HIT || st == MINE_SHOWN || st == WRONG_FLAG;
	float spread = 2.0;
	if (!chip) {
		if (floor_near(c, lp, cs, pitch, vec2(0.0), spread)
				|| floor_near(c, lp, cs, pitch, vec2(1.0, 0.0), spread)
				|| floor_near(c, lp, cs, pitch, vec2(0.0, 1.0), spread)
				|| floor_near(c, lp, cs, pitch, vec2(1.0, 1.0), spread)) {
			col = c_floor.rgb;
		}
	} else if (open_here) {
		col = c_floor.rgb;
		// fresh reveal: the floor flashes from 45% accent back to floor over 260 ms
		if (st == OPEN && age >= 0.0 && age < 260.0) {
			col = mix(col, c_accent.rgb, 0.45 * (1.0 - age / 260.0) * mix(0.5, 1.0, motion));
		}
		// inset hairline
		float e = min(min(lp.x, lp.y), min(cs - lp.x, cs - lp.y));
		if (e < 1.0) col = mix(c_floor.rgb, c_grid.rgb, 0.7);
	}

	// --- hidden chip ------------------------------------------------------------
	bool hidden_here = st == HIDDEN || st == FLAG;
	if (chip && hidden_here) {
		float cut = 0.16 * cs;
		if (lp.x + lp.y >= cut) {
			bool is_hover = c == hover;
			bool is_chord = st == HIDDEN && chord.x < 1e8 && max(abs(c.x - chord.x), abs(c.y - chord.y)) == 1.0;
			vec3 tile = c_tile.rgb;
			if (is_chord) tile = mix(c_tile.rgb, c_accent.rgb, 0.18);
			if (is_hover) tile = mix(c_tile.rgb, c_accent.rgb, 0.30);
			col = tile;
			if (lp.x < 1.0 || lp.y < 1.0) col = is_hover ? c_accent.rgb : c_edge.rgb;
			if (is_hover && (lp.x > cs - 1.0 || lp.y > cs - 1.0 || lp.x + lp.y < cut + 1.4)) col = c_accent.rgb;

			if (st == HIDDEN) {
				// cipher byte, re-rolling in a slow diagonal wave
				float phase = drift_ms - 80.0 * (c.x + c.y);
				float epoch = floor(phase / 4200.0);
				float since = mod(phase, 4200.0);
				float byte = floor(hash12(c * 1.37 + epoch * 17.0) * 256.0);
				float wave = 0.5 + 0.5 * sin(c.x * 0.42 + c.y * 0.31 + vnoise(c * 0.2) * 4.0);
				float co = 0.18 + 0.82 * pow(wave, 2.2);
				co = min(1.0, co + 0.5 * motion * exp(-since / 260.0));
				float fh = 0.22 * cs;
				float box = fh * GLYPH_BOX;
				float adv = fh * (hex_advance + 0.02);
				vec2 right = vec2(cs * 0.88, cs * 0.90 - fh * 0.62);
				vec2 c1 = right - vec2(adv * 0.5, 0.0);
				vec2 c0 = c1 - vec2(adv, 0.0);
				float hi_nib = floor(byte / 16.0);
				float lo_nib = mod(byte, 16.0);
				float a = atlas(glyphs, mod(hi_nib, 8.0), 1.0 + floor(hi_nib / 8.0), box_uv(lp, c0 + vec2(0.0, hex_dy * box), box))
					+ atlas(glyphs, mod(lo_nib, 8.0), 1.0 + floor(lo_nib / 8.0), box_uv(lp, c1 + vec2(0.0, hex_dy * box), box));
				vec3 ink = is_hover ? c_void.rgb : c_cipher.rgb;
				col = mix(col, ink, clamp(a, 0.0, 1.0) * (is_hover ? 1.0 : co));
			} else {
				// flag: drops in from 120% scale
				float drop = age < 90.0 && age >= 0.0 ? 1.0 + 0.2 * (1.0 - age / 90.0) : 1.0;
				float box = 0.5 * cs * SHAPE_BOX * drop;
				float a = atlas(glyphs, 0.0, 3.0, box_uv(lp, centre, box));
				col = mix(col, mix(c_tile.rgb, c_warn.rgb, 0.82), a);
			}
		}
	}

	// --- glows (from this cell and its neighbours, so halos aren't clipped) ------
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 off = vec2(float(i), float(j));
			vec4 nd = cell_data(c + off);
			int ns = state_of(nd);
			float nage = age_of(nd);
			vec2 q = lp - off * pitch;   // point relative to that cell's chip
			if (ns == OPEN && nage >= 120.0) {
				int nn = number_of(nd);
				if (nn > 0) {
					vec3 nc = nums[nn - 1].rgb;
					float bloom = 1.0 + 1.2 * exp(-(nage - 120.0) / 200.0);
					float box = number_px * GLYPH_BOX;
					vec2 uv = box_uv(q, centre + vec2(0.0, digit_dy * box), box);
					float gl = atlas(glow_l, float(nn - 1), 0.0, uv);
					float gs = atlas(glow_s, float(nn - 1), 0.0, uv);
					col = mix(col, nc, clamp(0.35 * gl * bloom, 0.0, 1.0));
					col = mix(col, nc, clamp(0.70 * gs * bloom, 0.0, 1.0));
				}
			} else if (ns == HIT) {
				vec4 hz = hazard(q, cs, nage);
				if (hz.a > 0.0) {
					col = hz.rgb;
				} else {
					// box-shadow: 0 0 18px danger at 55%
					vec2 dd = max(max(-q, q - vec2(cs)), vec2(0.0));
					float dist = length(dd);
					if (dist > 0.0) col = mix(col, c_danger.rgb, 0.55 * exp(-dist / (6.0 * max(zoom, 0.5))));
				}
			}
		}
	}

	// --- glyphs on this cell ----------------------------------------------------
	if (chip && st == OPEN) {
		if (age >= 0.0 && age < 120.0) {
			// decrypting: the byte scrambles through a few random values
			float byte = floor(hash12(c + floor(age / 34.0) * 7.31) * 256.0);
			float fh = number_px * 0.62;
			float box = fh * GLYPH_BOX;
			float adv = fh * (hex_advance + 0.02);
			float hi_nib = floor(byte / 16.0);
			float lo_nib = mod(byte, 16.0);
			vec2 y = vec2(0.0, hex_dy * box);
			float a = atlas(glyphs, mod(hi_nib, 8.0), 1.0 + floor(hi_nib / 8.0), box_uv(lp, centre - vec2(adv * 0.5, 0.0) + y, box))
				+ atlas(glyphs, mod(lo_nib, 8.0), 1.0 + floor(lo_nib / 8.0), box_uv(lp, centre + vec2(adv * 0.5, 0.0) + y, box));
			vec3 sc = num > 0 ? nums[num - 1].rgb : c_accent.rgb;
			col = mix(col, sc, clamp(a, 0.0, 1.0) * 0.85);
		} else if (num > 0) {
			float box = number_px * GLYPH_BOX;
			float a = atlas(glyphs, float(num - 1), 0.0, box_uv(lp, centre + vec2(0.0, digit_dy * box), box));
			col = mix(col, nums[num - 1].rgb, a);
		}
	}
	if (chip && st == MINE_SHOWN) {
		float box = 0.7 * cs * SHAPE_BOX;
		vec2 uv = box_uv(lp, centre, box);
		col = mix(col, c_ink_dim.rgb, atlas(glyphs, 1.0, 3.0, uv));
		col = mix(col, c_void.rgb, atlas(glyphs, 2.0, 3.0, uv));
	}
	if (chip && st == WRONG_FLAG) {
		col = c_floor.rgb;
		float e = min(min(lp.x, lp.y), min(cs - lp.x, cs - lp.y));
		if (e < 1.0) col = mix(c_floor.rgb, c_grid.rgb, 1.0);
		float box = 0.5 * cs * SHAPE_BOX;
		col = mix(col, c_ink_dim.rgb, atlas(glyphs, 0.0, 3.0, box_uv(lp, centre, box)));
		// a red X over the inner 56% of the cell
		vec2 u = (lp - vec2(0.22 * cs)) / (0.56 * cs);
		if (u.x >= 0.0 && u.y >= 0.0 && u.x <= 1.0 && u.y <= 1.0) {
			float t = 0.08 * 0.7071;
			if (abs(u.x - u.y) < t || abs(u.x + u.y - 1.0) < t) col = c_danger.rgb;
		}
	}

	COLOR = vec4(col, 1.0);
}
