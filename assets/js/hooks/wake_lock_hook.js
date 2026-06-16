const STORAGE_KEY = "museum-caper:wake-lock"

const WakeLockHook = {
  mounted() {
    this.button = this.el.querySelector("#wake-lock-toggle")
    this.status = this.el.querySelector("#wake-lock-status")
    this.indicator = this.el.querySelector("[data-wake-indicator]")
    this.sentinel = null
    this.enabled = localStorage.getItem(STORAGE_KEY) === "true"
    this.onVisibilityChange = () => this.handleVisibilityChange()
    this.onToggle = () => this.toggle()

    this.button.addEventListener("click", this.onToggle)
    document.addEventListener("visibilitychange", this.onVisibilityChange)

    if (!this.supported()) {
      this.enabled = false
      localStorage.removeItem(STORAGE_KEY)
      this.button.disabled = true
      this.setStatus("Not supported")
      return
    }

    if (this.enabled) {
      this.requestWakeLock()
    } else {
      this.setStatus("Off")
    }
  },

  destroyed() {
    this.button.removeEventListener("click", this.onToggle)
    document.removeEventListener("visibilitychange", this.onVisibilityChange)
    this.releaseWakeLock()
  },

  supported() {
    return "wakeLock" in navigator
  },

  async toggle() {
    if (this.enabled) {
      this.enabled = false
      localStorage.removeItem(STORAGE_KEY)
      await this.releaseWakeLock()
      this.setStatus("Off")
      return
    }

    this.enabled = true
    localStorage.setItem(STORAGE_KEY, "true")
    await this.requestWakeLock()
  },

  async requestWakeLock() {
    if (!this.enabled) return

    if (this.sentinel) {
      this.setStatus("On")
      return
    }

    if (document.visibilityState !== "visible") {
      this.setStatus("Paused")
      return
    }

    try {
      this.sentinel = await navigator.wakeLock.request("screen")
      this.sentinel.addEventListener("release", () => {
        this.sentinel = null
        this.setStatus(this.enabled ? "Paused" : "Off")
      })
      this.setStatus("On")
    } catch (_error) {
      this.sentinel = null
      this.enabled = false
      localStorage.removeItem(STORAGE_KEY)
      this.setStatus("Blocked")
    }
  },

  async releaseWakeLock() {
    if (!this.sentinel) return

    const sentinel = this.sentinel
    this.sentinel = null
    await sentinel.release()
  },

  handleVisibilityChange() {
    if (document.visibilityState === "visible") {
      this.requestWakeLock()
    }
  },

  setStatus(status) {
    this.status.textContent = status
    this.button.setAttribute("aria-pressed", this.enabled ? "true" : "false")
    this.indicator.className = [
      "size-2 shrink-0 rounded-full shadow-sm shadow-black/40",
      status === "On" && "bg-emerald-300",
      status === "Paused" && "bg-amber-300",
      status !== "On" && status !== "Paused" && "bg-stone-600"
    ].filter(Boolean).join(" ")
  }
}

export default WakeLockHook
