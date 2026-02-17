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

from PySide6.QtCore import Signal, Slot, Property, QPointF, QObject, Qt, QTimer
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
    panXChanged = Signal()
    panYChanged = Signal()
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
        self._pan_x = 0.0
        self._pan_y = 0.0

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
        self._fast_mode = False

        # Pre-computed color arrays (rebuilt on data load)
        self._colors_cache = []

        # Selection
        self._selected_info = ""
        self._selected_index = -1

        # Scatter artist screen coords cache (for picking)
        self._scatter_screen_coords = []

        # Render throttle: limits redraws to ~20 FPS during interaction
        self._render_timer = QTimer(self)
        self._render_timer.setInterval(50)
        self._render_timer.setSingleShot(True)
        self._render_timer.timeout.connect(self._on_render_tick)

        # Full-quality timer: fires after interaction stops
        self._quality_timer = QTimer(self)
        self._quality_timer.setInterval(400)
        self._quality_timer.setSingleShot(True)
        self._quality_timer.timeout.connect(self._on_quality_tick)

    # ---- QML Properties ----

    def _get_elev(self):
        return self._elev

    def _set_elev(self, v):
        if self._elev != v:
            self._elev = v
            self.elevChanged.emit()
            self._schedule_update()

    elev = Property(float, _get_elev, _set_elev, notify=elevChanged)

    def _get_azim(self):
        return self._azim

    def _set_azim(self, v):
        if self._azim != v:
            self._azim = v
            self.azimChanged.emit()
            self._schedule_update()

    azim = Property(float, _get_azim, _set_azim, notify=azimChanged)

    def _get_zoom(self):
        return self._zoom

    def _set_zoom(self, v):
        v = max(0.05, min(3.0, v))
        if self._zoom != v:
            self._zoom = v
            self.zoomChanged.emit()
            self._schedule_update()

    zoom = Property(float, _get_zoom, _set_zoom, notify=zoomChanged)

    def _get_pan_x(self):
        return self._pan_x

    def _set_pan_x(self, v):
        if self._pan_x != v:
            self._pan_x = v
            self.panXChanged.emit()
            self._schedule_update()

    panX = Property(float, _get_pan_x, _set_pan_x, notify=panXChanged)

    def _get_pan_y(self):
        return self._pan_y

    def _set_pan_y(self, v):
        if self._pan_y != v:
            self._pan_y = v
            self.panYChanged.emit()
            self._schedule_update()

    panY = Property(float, _get_pan_y, _set_pan_y, notify=panYChanged)

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

    def _get_xz_half(self):
        return self._xz_half

    xzHalf = Property(float, _get_xz_half, notify=pointCountChanged)

    def _get_y_half(self):
        return self._y_half

    yHalf = Property(float, _get_y_half, notify=pointCountChanged)

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

        # Pre-compute gap colors
        self._colors_cache = []
        if self._gaps:
            for g in self._gaps:
                t = ((g - self._gap_min) / (self._gap_max - self._gap_min)
                     if self._gap_max > self._gap_min else 0.0)
                self._colors_cache.append(_gap_to_rgba(t))

        self._loaded = True
        self._dirty = True
        self._fast_mode = False
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

    # ---- Render scheduling ----

    def _schedule_update(self):
        """Mark dirty and schedule a throttled re-render."""
        self._dirty = True
        self._fast_mode = True
        # Start throttle timer if not already running
        if not self._render_timer.isActive():
            self._render_timer.start()
        # Reset the full-quality timer
        self._quality_timer.start()

    def _on_render_tick(self):
        """Throttle timer fired — trigger a paint if still dirty."""
        if self._dirty:
            self.update()

    def _on_quality_tick(self):
        """Interaction stopped — render full quality."""
        self._fast_mode = False
        self._dirty = True
        self.update()

    # ---- Rendering ----

    def _render_plot(self, fast=False):
        """Render the matplotlib figure to a QImage.
        If fast=True, skip expensive elements (cylinder, colorbar, picking coords)
        and use lower DPI for responsive interaction.
        """
        w = int(self.width())
        h = int(self.height())
        if w <= 0 or h <= 0:
            return

        dpi = 60 if fast else 100
        fig_w = w / dpi
        fig_h = h / dpi

        fig = plt.figure(figsize=(fig_w, fig_h), dpi=dpi)
        fig.patch.set_facecolor("none")
        fig.patch.set_alpha(0.0)
        ax = fig.add_subplot(111, projection="3d")
        ax.set_box_aspect((1, 1, 1))
        ax.set_facecolor("none")

        # Remove all axis decorations (panes, spines, grid, ticks, labels)
        ax.set_axis_off()

        if self._loaded and self._base_x:
            # Base path
            ax.plot(self._base_x, self._base_y, self._base_z,
                    linestyle="-", linewidth=2.0, alpha=0.7,
                    label="Base Path (Nominal)", color="#FF4FF5")

            # Actual path
            ax.plot(self._actual_x, self._actual_y, self._actual_z,
                    linewidth=1.8, alpha=0.9,
                    label="Actual Path", color="#4FFBFF")

            # Scatter points colored by gap
            n = len(self._actual_x)
            colors = self._colors_cache if self._colors_cache else [(0, 1, 0, 1)] * n
            pt_size = 12 if fast else 25
            sizes = [pt_size] * n
            edge_colors = ["none"] * n
            if not fast and self._selected_index >= 0 and self._selected_index < n:
                sizes[self._selected_index] = 50
                edge_colors[self._selected_index] = "white"

            ax.scatter(
                self._actual_x, self._actual_y, self._actual_z,
                c=colors, s=sizes, depthshade=False,
                edgecolors=edge_colors, linewidths=1.5 if not fast else 0
            )

            # Cylinder pipe (always rendered, fewer segments in fast mode)
            cyl_radius = (DEFAULT_CYL_DIAM_IN * INCH_TO_MM) / 2.0
            n_theta = 24 if fast else 60
            n_y = 10 if fast else 30
            theta = np.linspace(0, 2 * np.pi, n_theta)
            y_line = np.linspace(self._y_min, self._y_max, n_y)
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

            if not fast:
                # Colorbar (expensive — skip during interaction)
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
                cbar.ax.set_facecolor("none")

            # Set limits (apply pan offsets)
            zm = self._zoom
            cx = self._center_x + self._pan_x
            cy = self._center_y + self._pan_y
            cz = self._center_z
            ax.set_xlim(cx - self._xz_half * zm,
                        cx + self._xz_half * zm)
            ax.set_ylim(cy - self._y_half * zm,
                        cy + self._y_half * zm)
            ax.set_zlim(cz - self._xz_half * zm,
                        cz + self._xz_half * zm)

            ax.view_init(elev=self._elev, azim=self._azim)

            if not fast:
                ax.legend(loc="upper left", facecolor="#11141F", edgecolor="#262B3D",
                          labelcolor="#E0E4FF", fontsize=8)

        plt.subplots_adjust(left=0.0, right=0.95, bottom=0.02, top=0.95)

        # Render to buffer — use raw format for speed in fast mode
        buf = io.BytesIO()
        fig.savefig(buf, format="raw" if fast else "png",
                    facecolor="none", edgecolor="none", transparent=True)
        buf.seek(0)

        if fast:
            # Raw RGBA buffer — much faster than PNG encode/decode
            raw_w = int(fig.get_figwidth() * fig.dpi)
            raw_h = int(fig.get_figheight() * fig.dpi)
            self._image = QImage(buf.getvalue(), raw_w, raw_h, QImage.Format_RGBA8888).copy()
        else:
            # Full quality PNG
            self._image = QImage()
            self._image.loadFromData(buf.getvalue())

            # Compute scatter screen coords for picking (only in full mode)
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
                        x2, y2, _ = proj3d.proj_transform(x3, y3, z3, ax.get_proj())
                        x2d, y2d = ax.transData.transform((x2, y2))
                        qml_x = x2d * (self.width() / fig_w_px)
                        qml_y = (fig_h_px - y2d) * (self.height() / fig_h_px)
                        self._scatter_screen_coords.append((qml_x, qml_y))
                except Exception:
                    self._scatter_screen_coords = []

        plt.close(fig)
        self._dirty = False

    def paint(self, painter: QPainter):
        if self._dirty or self._image is None:
            try:
                self._render_plot(fast=self._fast_mode)
            except Exception as e:
                print(f"[ScanPlotItem] render error: {e}")
                import traceback
                traceback.print_exc()
                self._dirty = False

        if self._image and not self._image.isNull():
            scaled = self._image.scaled(
                int(self.width()), int(self.height()),
                Qt.IgnoreAspectRatio,
                Qt.SmoothTransformation if not self._fast_mode else Qt.FastTransformation
            )
            painter.drawImage(0, 0, scaled)
        else:
            painter.fillRect(0, 0, int(self.width()), int(self.height()),
                             QColor("transparent"))
