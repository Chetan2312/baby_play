"""Optional single worker button on a GPIO pin (config: gpio_button).

Sends raw edges ("down" / "up") to the game; the game's InputRouter decides what a
short press, a 2 s press and a 5 s hold mean, the same way it does for the
presenter remote. Missing gpiozero or a busy pin gives an error string, not a crash.
"""


class GpioButton:
    def __init__(self, cfg, callback):
        self.cfg = cfg.get("gpio_button") or {}
        self.callback = callback
        self.error = None
        self._button = None

    @property
    def enabled(self):
        return bool(self.cfg.get("enabled", False))

    def start(self):
        if not self.enabled:
            return
        try:
            from gpiozero import Button
            b = Button(int(self.cfg.get("pin", 17)), pull_up=True,
                       bounce_time=float(self.cfg.get("bounce_s", 0.05)))
        except Exception as e:  # noqa: BLE001 - no gpiozero / pin busy / not a Pi
            self.error = f"GPIO button (pin {self.cfg.get('pin', 17)}): {e}"
            return
        b.when_pressed = lambda: self.callback("down")
        b.when_released = lambda: self.callback("up")
        self._button = b

    def stop(self):
        if self._button is not None:
            try:
                self._button.close()
            except Exception:  # noqa: BLE001
                pass
            self._button = None
