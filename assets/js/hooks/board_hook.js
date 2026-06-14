const BoardHook = {
  mounted() {
    this.scale = 1;
    this.startDist = null;

    this.el.addEventListener("touchstart", (e) => {
      if (e.touches.length === 2) {
        this.startDist = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY
        );
      }
    });

    this.el.addEventListener("touchmove", (e) => {
      if (e.touches.length === 2 && this.startDist) {
        e.preventDefault();
        const dist = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY
        );
        this.scale = Math.min(3, Math.max(0.5, this.scale * (dist / this.startDist)));
        this.startDist = dist;
        const grid = this.el.querySelector(".board-grid");
        if (grid) {
          grid.style.transform = `scale(${this.scale})`;
          grid.style.transformOrigin = "top left";
        }
      }
    }, { passive: false });

    this.el.addEventListener("touchend", () => {
      this.startDist = null;
    });
  }
};

export default BoardHook;
