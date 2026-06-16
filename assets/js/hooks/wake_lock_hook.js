const STORAGE_KEY = "museum-caper:wake-lock"

const WakeLockHook = {
  mounted() {
    this.button = this.el.querySelector("#wake-lock-toggle")
    this.status = this.el.querySelector("#wake-lock-status")
    this.indicator = this.el.querySelector("[data-wake-indicator]")
    this.sentinel = null
    this.fallbackVideo = null
    this.fallbackTimer = null
    this.fallbackFrame = false
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
    this.teardownFallbackVideo()
  },

  supported() {
    return this.nativeSupported() || this.fallbackSupported()
  },

  nativeSupported() {
    return "wakeLock" in navigator && typeof navigator.wakeLock.request === "function"
  },

  fallbackSupported() {
    const canvas = document.createElement("canvas")
    const video = document.createElement("video")

    return typeof canvas.captureStream === "function" && typeof video.play === "function"
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

    if (document.visibilityState !== "visible") {
      this.setStatus("Paused")
      return
    }

    if (this.nativeSupported() && (await this.requestNativeWakeLock())) {
      return
    }

    if (await this.requestFallbackWakeLock()) {
      return
    }

    this.enabled = false
    localStorage.removeItem(STORAGE_KEY)
    this.setStatus("Not supported")
  },

  async requestNativeWakeLock() {
    if (this.sentinel) {
      this.setStatus("On")
      return true
    }

    try {
      this.sentinel = await navigator.wakeLock.request("screen")
      this.sentinel.addEventListener("release", () => {
        this.sentinel = null
        this.setStatus(this.enabled ? "Paused" : "Off")
      })
      this.setStatus("On")
      return true
    } catch (_error) {
      this.sentinel = null
      return false
    }
  },

  async requestFallbackWakeLock() {
    if (!this.fallbackSupported()) return false

    try {
      const video = this.ensureFallbackVideo()
      await video.play()
      this.setStatus("On")
      return true
    } catch (_error) {
      this.releaseFallbackVideo()
      return false
    }
  },

  async releaseWakeLock() {
    if (this.sentinel) {
      const sentinel = this.sentinel
      this.sentinel = null
      await sentinel.release()
    }

    this.releaseFallbackVideo()
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
  },

  ensureFallbackVideo() {
    if (this.fallbackVideo) return this.fallbackVideo

    const canvas = document.createElement("canvas")
    canvas.width = 1
    canvas.height = 1

    const context = canvas.getContext("2d")
    const drawFrame = () => {
      this.fallbackFrame = !this.fallbackFrame
      context.fillStyle = this.fallbackFrame ? "#000" : "#111"
      context.fillRect(0, 0, 1, 1)
    }

    drawFrame()
    this.fallbackTimer = window.setInterval(drawFrame, 15000)

    const video = document.createElement("video")
    video.muted = true
    video.loop = true
    video.playsInline = true
    video.setAttribute("playsinline", "")
    video.setAttribute("aria-hidden", "true")
    video.style.position = "fixed"
    video.style.width = "1px"
    video.style.height = "1px"
    video.style.opacity = "0"
    video.style.pointerEvents = "none"
    video.srcObject = canvas.captureStream(1)

    this.el.appendChild(video)
    this.fallbackVideo = video

    return video
  },

  releaseFallbackVideo() {
    if (!this.fallbackVideo) return

    this.fallbackVideo.pause()
  },

  teardownFallbackVideo() {
    if (this.fallbackTimer) {
      window.clearInterval(this.fallbackTimer)
      this.fallbackTimer = null
    }

    if (this.fallbackVideo) {
      this.fallbackVideo.pause()
      this.fallbackVideo.remove()
      this.fallbackVideo = null
    }
  }
}

export default WakeLockHook
