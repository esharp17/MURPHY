import os
import csv
import xml.etree.ElementTree as ET

import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D  # noqa: F401
from matplotlib.widgets import Button, Slider
import numpy as np

# Hide the default toolbar
plt.rcParams["toolbar"] = "none"

# ----------------- CONFIG -----------------
MAX_POINTS   = 180
OFFSETS_XML = "offsets_norm.xml"
BASE_XML     = "base_points.xml"

INCH_TO_MM = 25.4
DEFAULT_CYL_DIAM_IN = 45.0
# ------------------------------------------


def find_base_dir():
    import sys
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.abspath(os.path.dirname(__file__))


def load_xml_points(path, max_points=MAX_POINTS):
    """
    Reads base_points.xml containing rows like:
      <row pos=" 1" x="..." y="..." z="..." .../>

    Returns: pos, xs, ys, zs
    """
    if not os.path.exists(path):
        raise FileNotFoundError(f"Could not find {path}")

    try:
        tree = ET.parse(path)
        root = tree.getroot()
    except ET.ParseError as e:
        raise ValueError(f"XML parse error in {path}: {e}")

    positions, xs, ys, zs = [], [], [], []

    for el in root.iter("row"):
        try:
            pos = int(float(el.attrib.get("pos", "0").strip() or "0"))
            x = float(el.attrib.get("x", "0").strip() or "0")
            y = float(el.attrib.get("y", "0").strip() or "0")
            z = float(el.attrib.get("z", "0").strip() or "0")
        except ValueError:
            continue

        positions.append(pos)
        xs.append(x); ys.append(y); zs.append(z)

        if len(positions) >= max_points:
            break

    if not positions:
        raise ValueError(f"No <row .../> elements found in {path}")
    
    return positions, xs, ys, zs, 0, 0
def load_offsets_xml(path, max_points=MAX_POINTS):
    """
    Reads OFFSETS.XML containing standalone row elements like:
      <row pos="   1" x="   0.000" y="   0.000" z="   0.000" g="   0.000" h="    .630" s=" 324"/>

    Returns: pos, xs, ys, zs, gaps, schedules
    (schedule defaults to 0 if attribute missing)
    """
    if not os.path.exists(path):
        raise FileNotFoundError(f"Could not find {path}")

    try:
        tree = ET.parse(path)
        root = tree.getroot()
    except ET.ParseError as e:
        raise ValueError(f"XML parse error in {path}: {e}")

    positions = []
    xs = []
    ys = []
    zs = []
    gaps = []
    schedules = []

    # Accept either:
    #   <offset_log> <row .../> ... </offset_log>
    # or a bare file with multiple <row/> (not valid XML) won’t parse.
    # So we assume you have a single root element containing rows.
    for el in root.iter("row"):
        try:
            pos = int(float(el.attrib.get("pos", "0").strip() or "0"))
            x = float(el.attrib.get("x", "0").strip() or "0")
            y = float(el.attrib.get("y", "0").strip() or "0")
            z = float(el.attrib.get("z", "0").strip() or "0")
            g = float(el.attrib.get("g", "0").strip() or "0")
            s = float(el.attrib.get("s", "0").strip() or "0")
        except ValueError:
            continue

        positions.append(pos)
        xs.append(x)
        ys.append(y)
        zs.append(z)
        gaps.append(g)
        schedules.append(s)

        if len(positions) >= max_points:
            break

    if not positions:
        raise ValueError(f"No <row .../> elements found in {path}")

    return positions, xs, ys, zs, gaps, schedules


def draw_nominal_cylinder_yaxis(ax, cx, cz, y_min, y_max, radius_mm,
                                n_theta=80, alpha=0.12):
    theta = np.linspace(0.0, 2.0 * np.pi, n_theta)
    y = np.array([y_min, y_max])

    theta_grid, y_grid = np.meshgrid(theta, y)
    x_grid = cx + radius_mm * np.cos(theta_grid)
    z_grid = cz + radius_mm * np.sin(theta_grid)

    rgba = np.ones(x_grid.shape + (4,))
    rgba[..., 0] = 0.25
    rgba[..., 1] = 0.7
    rgba[..., 2] = 1.0
    rgba[..., 3] = alpha

    surf = ax.plot_surface(
        x_grid, y_grid, z_grid,
        facecolors=rgba,
        linewidth=0,
        edgecolor="none",
        shade=False,
    )
    return surf


def main():
    base_dir = find_base_dir()
    offsets_path = os.path.join(base_dir, OFFSETS_XML)   # <-- changed
    base_path    = os.path.join(base_dir, BASE_XML)

    # Load data
    o_pos, o_x, o_y, o_z, o_gap, o_sched = load_offsets_xml(offsets_path)
    b_pos, b_x, b_y, b_z, b_gap, b_sched = load_xml_points(base_path)

    # Align by "pos" key (robust if either side has gaps)
    base_map = {int(p): (bx, by, bz) for p, bx, by, bz in zip(b_pos, b_x, b_y, b_z)}

    pos2 = []
    ox2, oy2, oz2, og2, os2 = [], [], [], [], []
    bx2, by2, bz2 = [], [], []

    for p, x, y, z, g, s in zip(o_pos, o_x, o_y, o_z, o_gap, o_sched):
        if p in base_map:
            bx, by, bz = base_map[p]
            pos2.append(p)
            ox2.append(x); oy2.append(y); oz2.append(z); og2.append(g); os2.append(s)
            bx2.append(bx); by2.append(by); bz2.append(bz)
        if len(pos2) >= MAX_POINTS:
            break

    if not pos2:
        raise ValueError("No overlapping positions between base_points.csv and offsets.xml")

    # Compute actual = base + offset
    a_x = [bx + dx for bx, dx in zip(bx2, ox2)]
    a_y = [by + dy for by, dy in zip(by2, oy2)]
    a_z = [bz + dz for bz, dz in zip(bz2, oz2)]

    print(f"Loaded {len(pos2)} points from:")
    print(f"  base    : {base_path}")
    print(f"  offsets : {offsets_path}")

    # ----------------- FIGURE & 3D PLOT -----------------
    fig = plt.figure(figsize=(9, 8))
    fig.patch.set_facecolor("#05060A")
    ax = fig.add_subplot(111, projection="3d")
    ax.set_box_aspect((1, 1, 1))
    ax.set_facecolor("none")

    fig.suptitle("Ring Weld Offsets (Base + Offsets)", fontsize=14, color="#E0E4FF")

    ax.grid(False)
    for axis in (ax.xaxis, ax.yaxis, ax.zaxis):
        axis._axinfo["grid"]["linewidth"] = 0
        axis._axinfo["grid"]["color"] = (0, 0, 0, 0)

    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_zticks([])
    try:
        ax.w_xaxis.line.set_lw(0.)
        ax.w_yaxis.line.set_lw(0.)
        ax.w_zaxis.line.set_lw(0.)
    except Exception:
        pass

    ax.plot(bx2, by2, bz2, linestyle="-", linewidth=2.0, alpha=0.7,
            label="Base Path (Nominal)", color="#FF4FF5")

    ax.plot(a_x, a_y, a_z, linewidth=1.8, alpha=0.9,
            label="Actual Path", color="#4FFBFF")

    sc = ax.scatter(
        a_x, a_y, a_z,
        c=og2,
        s=30,
        cmap="plasma",
        depthshade=False,
        picker=True,
        pickradius=5
    )

    cbar = fig.colorbar(sc, ax=ax, shrink=0.7)
    cbar.set_label("Gap (mm)", color="#E0E4FF")
    cbar.ax.yaxis.set_tick_params(color="#A8B0FF")
    for t in cbar.ax.get_yticklabels():
        t.set_color("#A8B0FF")
    cbar.ax.set_facecolor("#05060A")

    ax.set_xlabel("X (mm)", color="#A8B0FF")
    ax.set_ylabel("Y (mm)", color="#A8B0FF")
    ax.set_zlabel("Z (mm)", color="#A8B0FF")

    ax.legend(loc="upper left", facecolor="#11141F", edgecolor="#262B3D",
              labelcolor="#E0E4FF")

    all_x = bx2 + a_x
    all_y = by2 + a_y
    all_z = bz2 + a_z

    x_min, x_max = min(all_x), max(all_x)
    y_min, y_max = min(all_y), max(all_y)
    z_min, z_max = min(all_z), max(all_z)

    x_center = 0.5 * (x_min + x_max)
    y_center = 0.5 * (y_min + y_max)
    z_center = 0.5 * (z_min + z_max)

    x_half = 0.5 * (x_max - x_min)
    y_half = 0.5 * (y_max - y_min)
    z_half = 0.5 * (z_max - z_min)

    xz_half = max(x_half, z_half) * 1.05
    x_half_base = xz_half
    z_half_base = xz_half
    y_half_base = max(y_half, 1.0) * 1.3

    cyl_surface = None
    cyl_radius = (DEFAULT_CYL_DIAM_IN * INCH_TO_MM) / 2.0
    cyl_alpha = 0.25

    cyl_surface = draw_nominal_cylinder_yaxis(
        ax,
        cx=0.0,
        cz=0.0,
        y_min=y_min,
        y_max=y_max,
        radius_mm=cyl_radius,
        alpha=cyl_alpha,
    )

    zoom_factor = 1.0
    y_scale_factor = 10.0

    def apply_limits():
        x_half_zoom = x_half_base * zoom_factor
        z_half_zoom = z_half_base * zoom_factor
        y_half_zoom = y_half_base * zoom_factor * y_scale_factor

        ax.set_xlim(x_center - x_half_zoom, x_center + x_half_zoom)
        ax.set_ylim(y_center - y_half_zoom, y_center + y_half_zoom)
        ax.set_zlim(z_center - z_half_zoom, z_center + z_half_zoom)

    apply_limits()

    def update_cylinder():
        nonlocal cyl_surface
        if cyl_surface is not None:
            cyl_surface.remove()
            cyl_surface = None

        cyl_surface = draw_nominal_cylinder_yaxis(
            ax,
            cx=0.0,
            cz=0.0,
            y_min=y_min,
            y_max=y_max,
            radius_mm=cyl_radius * 0.97,
            alpha=cyl_alpha,
        )
        fig.canvas.draw_idle()

    def on_scroll(event):
        nonlocal zoom_factor
        if event.inaxes != ax:
            return
        base_scale = 0.9
        if event.button == "up":
            zoom_factor *= base_scale
        elif event.button == "down":
            zoom_factor /= base_scale
        else:
            return
        apply_limits()
        fig.canvas.draw_idle()

    fig.canvas.mpl_connect("scroll_event", on_scroll)

    btn_h = 0.05
    btn_w = 0.12
    btn_y = 0.01

    ax_btn_top   = fig.add_axes([0.05,  btn_y, btn_w, btn_h], facecolor="#11141F")
    ax_btn_side  = fig.add_axes([0.20, btn_y, btn_w, btn_h], facecolor="#11141F")
    ax_btn_front = fig.add_axes([0.35, btn_y, btn_w, btn_h], facecolor="#11141F")
    ax_btn_iso   = fig.add_axes([0.50, btn_y, btn_w, btn_h], facecolor="#11141F")

    btn_top   = Button(ax_btn_top,   "Top",   color="#11141F", hovercolor="#1E2433")
    btn_side  = Button(ax_btn_side,  "Side",  color="#11141F", hovercolor="#1E2433")
    btn_front = Button(ax_btn_front, "Front", color="#11141F", hovercolor="#1E2433")
    btn_iso   = Button(ax_btn_iso,   "Iso",   color="#11141F", hovercolor="#1E2433")

    for b in (btn_top, btn_side, btn_front, btn_iso):
        b.label.set_color("#E0E4FF")

    def set_view(elev, azim):
        ax.view_init(elev=elev, azim=azim)
        fig.canvas.draw_idle()

    def on_top(event):
        set_view(90, -90)

    def on_side(event):
        set_view(0, 0)

    def on_front(event):
        set_view(0, 90)

    iso_views = [(25, -60), (30, 30), (20, 140), (45, -120)]
    iso_index = {"i": 2}

    def on_iso(event):
        iso_index["i"] = (iso_index["i"] + 1) % len(iso_views)
        elev, azim = iso_views[iso_index["i"]]
        set_view(elev, azim)

    btn_top.on_clicked(on_top)
    btn_side.on_clicked(on_side)
    btn_front.on_clicked(on_front)
    btn_iso.on_clicked(on_iso)

    ax.view_init(elev=20, azim=140)

    ax_yslider = fig.add_axes([0.73, 0.115, 0.22, 0.03], facecolor="#11141F")
    y_slider = Slider(ax_yslider, "Y Scale", 3.0, 10.0, valinit=10.0, valstep=0.05)
    y_slider.label.set_color("#E0E4FF")
    y_slider.valtext.set_color("#A8B0FF")

    def on_y_scale(val):
        nonlocal y_scale_factor
        y_scale_factor = float(val)
        apply_limits()
        fig.canvas.draw_idle()

    y_slider.on_changed(on_y_scale)

    diam_min_in = 30.0
    diam_max_in = 60.0

    ax_cyl_d_slider = fig.add_axes([0.73, 0.075, 0.22, 0.03], facecolor="#11141F")
    cyl_d_slider = Slider(ax_cyl_d_slider, "Cyl Diam", diam_min_in, diam_max_in,
                          valinit=DEFAULT_CYL_DIAM_IN, valstep=1.0)
    cyl_d_slider.label.set_color("#E0E4FF")
    cyl_d_slider.valtext.set_color("#A8B0FF")

    def on_cyl_diam(val):
        nonlocal cyl_radius
        diam_in = float(val)
        cyl_radius = (diam_in * INCH_TO_MM) / 2.0
        update_cylinder()

    cyl_d_slider.on_changed(on_cyl_diam)

    ax_cyl_a_slider = fig.add_axes([0.73, 0.035, 0.22, 0.03], facecolor="#11141F")
    cyl_a_slider = Slider(ax_cyl_a_slider, "Transparency", 0.02, 1,
                          valinit=cyl_alpha, valstep=0.01)
    cyl_a_slider.label.set_color("#E0E4FF")
    cyl_a_slider.valtext.set_color("#A8B0FF")

    def on_cyl_alpha(val):
        nonlocal cyl_alpha
        cyl_alpha = float(val)
        update_cylinder()

    cyl_a_slider.on_changed(on_cyl_alpha)

    plt.subplots_adjust(left=0.05, right=0.95, bottom=0.17, top=0.88)

    info_text = fig.text(
        0.02, 0.95, "",
        ha="left", va="top",
        fontsize=10,
        color="#E0E4FF",
        bbox=dict(boxstyle="round,pad=0.3", facecolor="#11141F",
                  edgecolor="#262B3D", alpha=0.9)
    )

    def on_pick(event):
        if event.artist is not sc:
            return
        k = event.ind[0]

        pos = pos2[k]
        gap = og2[k]
        sched = os2[k]
        x = ox2[k]
        y = oy2[k]
        z = oz2[k]

        info_text.set_text(
            f"Pos: {pos}\n"
            f"X={x:.3f}, Y={y:.3f}, Z={z:.3f}\n"
            f"Gap={gap:.3f}, Sched={sched:g}"
        )
        fig.canvas.draw_idle()

    fig.canvas.mpl_connect("pick_event", on_pick)

    plt.show()


if __name__ == "__main__":
    main()
