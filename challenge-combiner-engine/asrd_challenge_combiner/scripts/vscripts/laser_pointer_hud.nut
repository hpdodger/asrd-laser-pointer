// laser_pointer_hud.nut — client-side script for rd_hud_vscript.
// One instance per player who uses the laser pointer; runs on EVERY client,
// so everyone sees everyone's laser.
//
// Slot contract (MUST match module_laser_pointer.nut):
//   GetEntity(0) = source marker          GetInt(0) = active
//   GetEntity(1) = endpoint marker        GetInt(1) = color index 0..7
//   GetEntity(2) = mark pulse anchor      GetInt(2) = draw line (0 in beam mode)
//   GetEntity(3) = owner player (unused)  GetFloat(0) = mark Time(), 0 = none
//                                         GetFloat(1) = mark pulse duration

SLOT_COLORS <- [
    [255,  50,  50],   // 0 red
    [  0, 220, 255],   // 1 cyan
    [ 50, 255,  50],   // 2 green
    [255, 220,   0],   // 3 yellow
    [255, 140,   0],   // 4 orange
    [255,  50, 255],   // 5 magenta
    [220, 220, 220],   // 6 white
    [160,  50, 255],   // 7 purple
];

// screen-space smoothing state (endpoint and source)
g_sx <- null;
g_sy <- null;
g_kx <- null;
g_ky <- null;

function OnUpdate() {}   // required: the engine warns if this is missing

function Paint() {
    local col = SLOT_COLORS[self.GetInt(1) % SLOT_COLORS.len()];

    DrawPulse(col);   // the pulse finishes playing even after the laser toggles off

    if (!self.GetInt(0)) { g_sx = null; g_kx = null; return; }

    local eTgt = self.GetEntity(1);
    if (eTgt == null || !eTgt.IsValid()) return;
    local spTgt = self.ClientGetEntityScreenPos(eTgt, false);
    if (spTgt == null) { g_sx = null; g_kx = null; return; }

    if (g_sx == null || fabs(spTgt.x - g_sx) > 150 || fabs(spTgt.y - g_sy) > 150) {
        g_sx = spTgt.x;   // snap on the first frame or after a jump
        g_sy = spTgt.y;
    } else {
        g_sx += (spTgt.x - g_sx) * 0.35;
        g_sy += (spTgt.y - g_sy) * 0.35;
    }

    if (self.GetInt(2)) {
        local eSrc = self.GetEntity(0);
        if (eSrc != null && eSrc.IsValid()) {
            // source marker sits at marine origin + src_height (no emote offset!)
            local spSrc = self.ClientGetEntityScreenPos(eSrc, false);
            if (spSrc != null) {
                if (g_kx == null || fabs(spSrc.x - g_kx) > 150 || fabs(spSrc.y - g_ky) > 150) {
                    g_kx = spSrc.x;
                    g_ky = spSrc.y;
                } else {
                    g_kx += (spSrc.x - g_kx) * 0.35;
                    g_ky += (spSrc.y - g_ky) * 0.35;
                }
                DrawLaserLine(g_kx, g_ky, g_sx, g_sy, col[0], col[1], col[2]);
            }
        }
    }

    // endpoint dot — in both modes
    local x = g_sx.tointeger();
    local y = g_sy.tointeger();
    self.PaintRectangle(x - 5, y - 5, x + 5, y + 5, col[0], col[1], col[2], 255);
    self.PaintRectangle(x - 2, y - 2, x + 2, y + 2, 255, 255, 255, 220);
}

function DrawLaserLine(x1, y1, x2, y2, R, G, B) {
    local dx = x2 - x1;
    local dy = y2 - y1;
    local len = sqrt(dx * dx + dy * dy);
    if (len < 2.0) return;
    local half  = 1.5;
    local steps = (len / 4.0).tointeger();
    if (steps < 1) steps = 1;
    for (local i = 0; i <= steps; i++) {
        local t  = i.tofloat() / steps.tofloat();
        local px = x1 + dx * t;
        local py = y1 + dy * t;
        local a  = 200 - (t * 80).tointeger();
        self.PaintRectangle((px - half).tointeger(), (py - half).tointeger(),
                            (px + half).tointeger(), (py + half).tointeger(), R, G, B, a);
    }
}

function DrawPulse(col) {
    local t0  = self.GetFloat(0);
    local dur = self.GetFloat(1);
    if (t0 <= 0 || dur <= 0) return;
    local t = (Time() - t0) / dur;
    if (t < 0 || t >= 1.0) return;

    local e = self.GetEntity(2);
    if (e == null || !e.IsValid()) return;
    local sp = self.ClientGetEntityScreenPos(e, false);
    if (sp == null) return;

    local x = sp.x.tointeger();
    local y = sp.y.tointeger();
    local h = (6 + 26 * t).tointeger();          // expanding half-size
    local a = (230 * (1.0 - t)).tointeger();     // fading alpha
    // square ring: 4 bars, 2px thick
    self.PaintRectangle(x - h, y - h, x + h, y - h + 2, col[0], col[1], col[2], a);
    self.PaintRectangle(x - h, y + h - 2, x + h, y + h, col[0], col[1], col[2], a);
    self.PaintRectangle(x - h, y - h, x - h + 2, y + h, col[0], col[1], col[2], a);
    self.PaintRectangle(x + h - 2, y - h, x + h, y + h, col[0], col[1], col[2], a);
}
