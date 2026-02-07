"""
Renders the Ring Weld Offsets 3D plot to a PNG image file (no GUI window).
Usage: python Plot_to_image.py [output_path]
  If output_path is omitted, writes to scan_plot.png in the same directory.
"""
import os
import sys
import xml.etree.ElementTree as ET
import numpy as np

# Use non-interactive backend so no window pops up
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D  # noqa: F401

MAX_POINTS = 180
OFFSETS_XML = "offsets_norm.xml"
BASE_XML = "base_points.xml"
INCH_TO_MM = 25.4
DEFAULT_CYL_DIAM_IN = 45.0


def find_base_dir():
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.abspath(os.path.dirname(__file__))


def load_xml_points(path, max_points=MAX_POINTS):
    if not os.path.exists(path):
        raise FileNotFoundError(f"Could not find {path}")
    tree = ET.parse(path)
    root = tree.getroot()
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
    return positions, xs, ys, zs


def load_offsets_xml(path, max_points=MAX_POINTS):
    if not os.path.exists(path):
        raise FileNotFoundError(f"Could not find {path}")
    tree = ET.parse(path)
    root = tree.getroot()
    positions, xs, ys, zs, gaps, scheds = [], [], [], [], [], []
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
        xs.append(x); ys.append(y); zs.append(z)
        gaps.append(g); scheds.append(s)
        if len(positions) >= max_points:
            break
    return positions, xs, ys, zs, gaps, scheds


def draw_nominal_cylinder_yaxis(ax, cx, cz, y_min, y_max, radius_mm, alpha=0.25):
    theta = np.linspace(0, 2 * np.pi, 60)
    y_line = np.linspace(y_min, y_max, 30)
    theta_grid, y_grid = np.meshgrid(theta, y_line)
    x_grid = cx + radius_mm * np.cos(theta_grid)
    z_grid = cz + radius_mm * np.sin(theta_grid)
    rgba = np.ones(x_grid.shape + (4,))
    rgba[..., 0] = 0.25
    rgba[..., 1] = 0.7
    rgba[..., 2] = 1.0
    rgba[..., 3] = alpha
    surf = ax.plot_surface(x_grid, y_grid, z_grid, facecolors=rgba,
                           linewidth=0, edgecolor="none", shade=False)
    return surf


def render_plot(output_path, elev=20, azim=140, zoom=1.0):
    base_dir = find_base_dir()
    offsets_path = os.path.join(base_dir, OFFSETS_XML)
    base_path = os.path.join(base_dir, BASE_XML)

    o_pos, o_x, o_y, o_z, o_gap, o_sched = load_offsets_xml(offsets_path)
    b_pos, b_x, b_y, b_z = load_xml_points(base_path)

    base_map = {int(p): (bx, by, bz) for p, bx, by, bz in zip(b_pos, b_x, b_y, b_z)}

    pos2 = []
    ox2, oy2, oz2, og2 = [], [], [], []
    bx2, by2, bz2 = [], [], []

    for p, x, y, z, g, s in zip(o_pos, o_x, o_y, o_z, o_gap, o_sched):
        if p in base_map:
            bx, by, bz = base_map[p]
            pos2.append(p)
            ox2.append(x); oy2.append(y); oz2.append(z); og2.append(g)
            bx2.append(bx); by2.append(by); bz2.append(bz)
        if len(pos2) >= MAX_POINTS:
            break

    if not pos2:
        raise ValueError("No overlapping positions between base and offsets")

    a_x = [bx + dx for bx, dx in zip(bx2, ox2)]
    a_y = [by + dy for by, dy in zip(by2, oy2)]
    a_z = [bz + dz for bz, dz in zip(bz2, oz2)]

    # Create figure
    fig = plt.figure(figsize=(12, 9), dpi=120)
    fig.patch.set_facecolor("#0d1117")
    ax = fig.add_subplot(111, projection="3d")
    ax.set_box_aspect((1, 1, 1))
    ax.set_facecolor("none")

    fig.suptitle("Ring Weld Offsets (Base + Offsets)", fontsize=16, color="#E0E4FF")

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

    sc = ax.scatter(a_x, a_y, a_z, c=og2, s=30, cmap="plasma", depthshade=False)

    cbar = fig.colorbar(sc, ax=ax, shrink=0.7)
    cbar.set_label("Gap (mm)", color="#E0E4FF")
    cbar.ax.yaxis.set_tick_params(color="#A8B0FF")
    for t in cbar.ax.get_yticklabels():
        t.set_color("#A8B0FF")
    cbar.ax.set_facecolor("#0d1117")

    ax.set_xlabel("X (mm)", color="#A8B0FF")
    ax.set_ylabel("Y (mm)", color="#A8B0FF")
    ax.set_zlabel("Z (mm)", color="#A8B0FF")

    ax.legend(loc="upper left", facecolor="#11141F", edgecolor="#262B3D",
              labelcolor="#E0E4FF")

    # Cylinder
    all_y = by2 + a_y
    y_min, y_max = min(all_y), max(all_y)
    cyl_radius = (DEFAULT_CYL_DIAM_IN * INCH_TO_MM) / 2.0
    draw_nominal_cylinder_yaxis(ax, cx=0.0, cz=0.0, y_min=y_min, y_max=y_max,
                                radius_mm=cyl_radius, alpha=0.25)

    # Set limits
    all_x = bx2 + a_x
    all_z = bz2 + a_z
    x_min, x_max = min(all_x), max(all_x)
    z_min, z_max = min(all_z), max(all_z)

    x_center = 0.5 * (x_min + x_max)
    y_center = 0.5 * (min(all_y) + max(all_y))
    z_center = 0.5 * (z_min + z_max)

    xz_half = max(0.5 * (x_max - x_min), 0.5 * (z_max - z_min)) * 1.05
    y_half = max(0.5 * (max(all_y) - min(all_y)), 1.0) * 1.3 * 10.0

    ax.set_xlim(x_center - xz_half * zoom, x_center + xz_half * zoom)
    ax.set_ylim(y_center - y_half * zoom, y_center + y_half * zoom)
    ax.set_zlim(z_center - xz_half * zoom, z_center + xz_half * zoom)

    ax.view_init(elev=elev, azim=azim)

    # Scan info text
    fig.text(0.02, 0.95,
             f"Scan: {len(pos2)}\nGap={og2[-1]:.3f}, Sched={o_sched[-1]:g}",
             ha="left", va="top", fontsize=10, color="#E0E4FF",
             bbox=dict(boxstyle="round,pad=0.3", facecolor="#11141F",
                       edgecolor="#262B3D", alpha=0.9))

    plt.subplots_adjust(left=0.02, right=0.95, bottom=0.05, top=0.90)

    fig.savefig(output_path, facecolor=fig.get_facecolor(), edgecolor="none",
                bbox_inches="tight", pad_inches=0.1)
    plt.close(fig)
    print(f"Plot saved to: {output_path}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("output", nargs="?", default=os.path.join(find_base_dir(), "scan_plot.png"))
    parser.add_argument("--elev", type=float, default=20)
    parser.add_argument("--azim", type=float, default=140)
    parser.add_argument("--zoom", type=float, default=1.0)
    args = parser.parse_args()
    render_plot(args.output, elev=args.elev, azim=args.azim, zoom=args.zoom)
