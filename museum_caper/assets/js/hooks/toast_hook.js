const ToastHook = {
  mounted() {
    this.scheduleHide();
  },
  updated() {
    clearTimeout(this.timer);
    this.el.style.opacity = "1";
    this.scheduleHide();
  },
  scheduleHide() {
    this.timer = setTimeout(() => {
      this.el.style.transition = "opacity 0.5s";
      this.el.style.opacity = "0";
    }, 4000);
  }
};

export default ToastHook;
