"""
ScanPlotItem - QQuickPaintedItem that renders the 3D scan plot in-process
using matplotlib with cached data. No subprocess needed.

Exposed to QML as a custom item that can be placed directly in the scene.
Supports interactive rotation (azimuth), zoom, and point picking.
"""
import os
import sys
import io
import numpy as np

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D  # noqa: F401

from PySide6.QtCore import Signal, Slot, Property, QPointF, QObject, Qt
from PySide6.QtGui import QImage, QPainter, QColor
from PySide6.QtQuick import QQuickPaintedItem

INCH_TO_MM = 25.4
DEFAULT_CYL_DIAM_IN = 45.0


def _gap_to_rgba(t):
    """Map normalized 0..1 to green->yellow->orange->red as RGBA tuple."""
    t = max(0.0, min(1.0, t))
    if t < 0.33:
        f = t / 0.33
        return (f, 1.0, 0.0, 1.0)
    elif t < 0.66:
        f = (t - 0.33) / 0.33
        return (1.0, 1.0 - f * 0.39, 0.0, 1.0)
    else:
        f = (t - 0.66) / 0.34
        return (1.0, 0.61 - f * 0.61, 0.0, 1.0)


class ScanPlotItem(QQuickPaintedItem):
    elevChanged = Signal()
    azimChanged = Signal()
    zoomChanged = Signal()
    selectedInfoChanged = Signal()
    pointCountChanged = Signal()
    gapRangeChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setRenderTarget(QQuickPaintedItem.FramebufferObject)
        self.setAntialiasing(True)

        # View state
        self._elev = 20.0
        self._azim = 140.0
        self._zoom = 1.0

        # Data (set by provider)
        self._base_x = []
        self._base_y = []
        self._base_z = []
        self._actual_x = []
        self._actual_y = []
        self._actual_z = []
        self._gaps = []
        self._schedules = []
        self._positions = []
        self._offset_x = []
        self._offset_y = []
        self._offset_z = []

        # Bounds
        self._center_x = 0.0
        self._center_y = 0.0
        self._center_z = 0.0
        self._xz_half = 500.0
        self._y_half = 500.0
        self._y_min = 0.0
        self._y_max = 0.0
        self._gap_min = 0.0
        self._gap_max = 1.0

        # Cached image
        self._image = None
        self._dirty = True
        self._loaded = False

        # Selection
        self._selected_info = ""
        self._selected_index = -1

        # Scatter artist screen coords cache (for picking)
        self._scatter_screen_coords = []

    # ---- QML Properties ----

    def _get_elev(self):
        return self._elev

    def _set_elev(self, v):
        if self._elev != v:
            self._elev = v
            self._dirty = True
            self.elevChanged.emit()
            self.update()

    elev = Property(float, _get_elev, _set_elev, notify=elevChanged)

    def _get_azim(self):
        return self._azim

    def _set_azim(self, v):
        if self._azim != v:
            self._azim = v
            self._dirty = True
            self.azimChanged.emit()
            self.update()

    azim = Property(float, _get_azim, _set_azim, notify=azimChanged)

    def _get_zoom(self):
        return self._zoom

    def _set_zoom(self, v):
        v = max(0.3, min(3.0, v))
        if self._zoom != v:
            self._zoom = v
            self._dirty = True
            self.zoomChanged.emit()
            self.update()

    zoom = Property(float, _get_zoom, _set_zoom, notify=zoomChanged)

    def _get_selected_info(self):
        return self._selected_info

    selectedInfo = Property(str, _get_selected_info, notify=selectedInfoChanged)

    def _get_point_count(self):
        return len(self._positions)

    pointCount = Property(int, _get_point_count, notify=pointCountChanged)

    def _get_gap_range_str(self):
        if not self._gaps:
            return ""
        return f"Gap: {self._gap_min:.3f} - {self._gap_max:.3f} mm"

    gapRange = Property(str, _get_gap_range_str, notify=gapRangeChanged)

    # ---- Data loading ----

    @Slot(QObject)
    def loadFromProvider(self, provider):
        """Load data directly from a ScanDataProvider QObject."""
        if provider is None:
            return

        base_pts = provider.getBasePoints()
        actual_pts = provider.getActualPoints()
        gaps = provider.getGaps()
        schedules = provider.getSchedules()
        positions = provider.getPositions()

        self._base_x = [p[0] for p in base_pts]
        self._base_y = [p[1] for p in base_pts]
        self._base_z = [p[2] for p in base_pts]
        self._actual_x = [p[0] for p in actual_pts]
        self._actual_y = [p[1] for p in actual_pts]
        self._actual_z = [p[2] for p in actual_pts]
        self._gaps = list(gaps)
        self._schedules = list(schedules)
        self._positions = list(positions)
        self._offset_x = [a[0] - b[0] for a, b in zip(actual_pts, base_pts)]
        self._offset_y = [a[1] - b[1] for a, b in zip(actual_pts, base_pts)]
        self._offset_z = [a[2] - b[2] for a, b in zip(actual_pts, base_pts)]

        # Compute bounds
        if self._base_x:
            all_x = self._base_x + self._actual_x
            all_y = self._base_y + self._actual_y
            all_z = self._base_z + self._actual_z

            self._center_x = 0.5 * (min(all_x) + max(all_x))
            self._center_y = 0.5 * (min(all_y) + max(all_y))
            self._center_z = 0.5 * (min(all_z) + max(all_z))

            x_half = 0.5 * (max(all_x) - min(all_x))
            z_half = 0.5 * (max(all_z) - min(all_z))
            self._xz_half = max(x_half, z_half) * 1.05
            self._y_half = max(0.5 * (max(all_y) - min(all_y)), 1.0) * 1.3 * 10.0
            self._y_min = min(all_y)
            self._y_max = max(all_y)

            if self._gaps:
                self._gap_min = min(self._gaps)
                self._gap_max = max(self._gaps)
                if self._gap_max == self._gap_min:
                    self._gap_max = self._gap_min + 1.0

        self._loaded = True
        self._dirty = True
        self.pointCountChanged.emit()
        self.gapRangeChanged.emit()
        self.update()

    # ---- Picking ----

    @Slot(float, float)
    def pickPoint(self, qml_x, qml_y):
        """Find the nearest scatter point to the click position."""
        if not self._scatter_screen_coords or not self._positions:
            return

        w = self.width()
        h = self.height()
        if w <= 0 or h <= 0:
            return

        best_dist = float("inf")
        best_idx = -1

        for i, (sx, sy) in enumerate(self._scatter_screen_coords):
            dx = sx - qml_x
            dy = sy - qml_y
            dist = dx * dx + dy * dy
            if dist < best_dist:
                best_dist = dist
                best_idx = i

        # Only pick if within 20px
        if best_dist < 400 and best_idx >= 0:
            self._selected_index = best_idx
            pos = self._positions[best_idx]
            gap = self._gaps[best_idx]
            sched = self._schedules[best_idx]
            ox = self._offset_x[best_idx]
            oy = self._offset_y[best_idx]
            oz = self._offset_z[best_idx]
            self._selected_info = (
                f"Pos: {pos}  |  Gap: {gap:.3f}mm  |  Sched: {sched:g}  |  "
                f"Offset: X={ox:.3f}, Y={oy:.3f}, Z={oz:.3f}"
            )
        else:
            self._selected_index = -1
            self._selected_info = ""

        self.selectedInfoChanged.emit()
        self._dirty = True
        self.update()

    # ---- Rendering ----

    def _render_plot(self):
        """Render the matplotlib figure to a QImage."""
        w = int(self.width())
        h = int(self.height())
        if w <= 0 or h <= 0:
            return

        dpi = 100
        fig_w = w / dpi
        fig_h = h / dpi

        fig = plt.figure(figsize=(fig_w, fig_h), dpi=dpi)
        fig.patch.set_facecolor("#0d1117")
        ax = fig.add_subplot(111, projection="3d")
        ax.set_box_aspect((1, 1, 1))
        ax.set_facecolor("none")

        # Remove grid and axes
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

        if self._loaded and self._base_x:
            # Base path
            ax.plot(self._base_x, self._base_y, self._base_z,
                    linestyle="-", linewidth=2.0, alpha=0.7,
                    label="Base Path (Nominal)", color="#FF4FF5")

            # Actual path
            ax.plot(self._actual_x, self._actual_y, self._actual_z,
                    linewidth=1.8, alpha=0.9,
                    label="Actual Path", color="#4FFBFF")

            # Scatter points colored by gap (green->yellow->orange->red)
            n = len(self._actual_x)
            colors = []
            for i in range(n):
                t = ((self._gaps[i] - self._gap_min) / (self._gap_max - self._gap_min)
                     if self._gap_max > self._gap_min else 0.0)
                colors.append(_gap_to_rgba(t))

            sizes = [50 if i == self._selected_index else 25 for i in range(n)]
            edge_colors = ["white" if i == self._selected_index else "none" for i in range(n)]

            sc = ax.scatter(
                self._actual_x, self._actual_y, self._actual_z,
                c=colors, s=sizes, depthshade=False,
                edgecolors=edge_colors, linewidths=1.5
            )

            # Colorbar-like legend
            import matplotlib.colors as mcolors
            from matplotlib.cm import ScalarMappable
            cmap_colors = [_gap_to_rgba(t) for t in np.linspace(0, 1, 256)]
            cmap = mcolors.ListedColormap(cmap_colors)
            norm = mcolors.Normalize(vmin=self._gap_min, vmax=self._gap_max)
            sm = ScalarMappable(cmap=cmap, norm=norm)
            sm.set_array([])
            cbar = fig.colorbar(sm, ax=ax, shrink=0.6, pad=0.02)
            cbar.set_label("Gap (mm)", color="#E0E4FF", fontsize=9)
            cbar.ax.yaxis.set_tick_params(color="#A8B0FF", labelsize=8)
            for t in cbar.ax.get_yticklabels():
                t.set_color("#A8B0FF")
            cbar.ax.set_facecolor("#0d1117")

            # Cylinder
            cyl_radius = (DEFAULT_CYL_DIAM_IN * INCH_TO_MM) / 2.0
            theta = np.linspace(0, 2 * np.pi, 60)
            y_line = np.linspace(self._y_min, self._y_max, 30)
            theta_grid, y_grid = np.meshgrid(theta, y_line)
            x_grid = 0.0 + cyl_radius * np.cos(theta_grid)
            z_grid = 0.0 + cyl_radius * np.sin(theta_grid)
            rgba = np.ones(x_grid.shape + (4,))
            rgba[..., 0] = 0.25
            rgba[..., 1] = 0.7
            rgba[..., 2] = 1.0
            rgba[..., 3] = 0.15
            ax.plot_surface(x_grid, y_grid, z_grid, facecolors=rgba,
                            linewidth=0, edgecolor="none", shade=False)

            # Set limits
            zm = self._zoom
            ax.set_xlim(self._center_x - self._xz_half * zm,
                        self._center_x + self._xz_half * zm)
            ax.set_ylim(self._center_y - self._y_half * zm,
                        self._center_y + self._y_half * zm)
            ax.set_zlim(self._center_z - self._xz_half * zm,
                        self._center_z + self._xz_half * zm)

            ax.view_init(elev=self._elev, azim=self._azim)

            ax.legend(loc="upper left", facecolor="#11141F", edgecolor="#262B3D",
                      labelcolor="#E0E4FF", fontsize=8)

            # Title
            fig.suptitle("Ring Weld Scan", fontsize=14, color="#E0E4FF", y=0.96)

        plt.subplots_adjust(left=0.0, right=0.95, bottom=0.02, top=0.92)

        # Render to buffer
        buf = io.BytesIO()
        fig.savefig(buf, format="png", facecolor=fig.get_facecolor(),
                    edgecolor="none", bbox_inches="tight", pad_inches=0.05)
        buf.seek(0)

        # Compute scatter screen coords for picking
        self._scatter_screen_coords = []
        if self._loaded and self._actual_x:
            try:
                from mpl_toolkits.mplot3d import proj3d
                renderer = fig.canvas.get_renderer()
                fig.draw(renderer)
                fig_w_px = fig.get_figwidth() * fig.dpi
                fig_h_px = fig.get_figheight() * fig.dpi
                for i in range(len(self._actual_x)):
                    x3 = self._actual_x[i]
                    y3 = self._actual_y[i]
                    z3 = self._actual_z[i]
                    # Project 3D data coords to 2D display coords
                    x2, y2, _ = proj3d.proj_transform(x3, y3, z3, ax.get_proj())
                    x2d, y2d = ax.transData.transform((x2, y2))
                    # Convert from matplotlib coords (bottom-left origin) to QML coords (top-left)
                    qml_x = x2d * (self.width() / fig_w_px)
                    qml_y = (fig_h_px - y2d) * (self.height() / fig_h_px)
                    self._scatter_screen_coords.append((qml_x, qml_y))
            except Exception:
                self._scatter_screen_coords = []

        plt.close(fig)

        # Load QImage from buffer
        self._image = QImage()
        self._image.loadFromData(buf.getvalue())
        self._dirty = False

    def paint(self, painter: QPainter):
        if self._dirty or self._image is None:
            try:
                self._render_plot()
            except Exception as e:
                print(f"[ScanPlotItem] render error: {e}")
                import traceback
                traceback.print_exc()
                self._dirty = False

        if self._image and not self._image.isNull():
            # Scale image to fill the item
            scaled = self._image.scaled(
                int(self.width()), int(self.height()),
                Qt.IgnoreAspectRatio,
                Qt.SmoothTransformation
            )
            painter.drawImage(0, 0, scaled)
        else:
            painter.fillRect(0, 0, int(self.width()), int(self.height()),
                             QColor("#0d1117"))
