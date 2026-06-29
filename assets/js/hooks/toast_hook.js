const seenToastKeys = new Set();
const DEFAULT_TOAST_DURATION_MS = 4000;

export const toastDuration = el => {
  const duration = Number.parseInt(
    el?.dataset?.toastDuration || `${DEFAULT_TOAST_DURATION_MS}`,
    10
  );

  return Number.isFinite(duration) && duration > 0 ? duration : DEFAULT_TOAST_DURATION_MS;
};

const ToastHook = {
  mounted() {
    this.showIfNew();
  },
  updated() {
    this.showIfNew();
  },
  destroyed() {
    clearTimeout(this.timer);
  },
  showIfNew() {
    const key = this.toastKey();

    if (seenToastKeys.has(key)) {
      this.hideImmediately();
      return;
    }

    seenToastKeys.add(key);
    this.show();
  },
  toastKey() {
    return this.el.dataset.toastKey || this.el.textContent.trim().replace(/\s+/g, " ");
  },
  show() {
    clearTimeout(this.timer);
    this.el.style.transition = "opacity 0.5s, transform 0.5s";
    this.el.style.opacity = "1";
    this.el.style.transform = "translateY(0)";
    this.scheduleHide();
  },
  scheduleHide() {
    this.timer = setTimeout(() => {
      this.el.style.transition = "opacity 0.5s, transform 0.5s";
      this.el.style.opacity = "0";
      this.el.style.transform = "translateY(0.5rem)";
    }, toastDuration(this.el));
  },
  hideImmediately() {
    clearTimeout(this.timer);
    this.el.style.transition = "none";
    this.el.style.opacity = "0";
    this.el.style.transform = "translateY(0.5rem)";
  }
};

export default ToastHook;
