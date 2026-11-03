import numpy as np
import pytest

from takatak_vision import camera_v4l2 as V
from takatak_vision.config import load_config


@pytest.fixture
def cam():
    return V.V4l2CameraThread(load_config(profile="n150"))


def test_frames_keep_the_bundle_contract(cam):
    main = np.zeros((1080, 1920, 4), np.uint8)
    main[..., 0], main[..., 2] = 200, 10            # RGBX: red
    main, lores = cam._frames(main)
    assert main.shape == (1080, 1920, 4) and lores.shape == (360, 640, 3)
    assert lores[0, 0, 2] == 200 and lores[0, 0, 0] == 10   # lores is BGR


def test_frames_rescale_another_camera_size(cam):
    main, lores = cam._frames(np.zeros((720, 1280, 4), np.uint8))
    assert main.shape == (1080, 1920, 4) and lores.shape == (360, 640, 3)


@pytest.mark.parametrize("rotation,main_shape,lores_shape", [
    ("inverted", (1080, 1920, 4), (360, 640, 3)),
    ("right", (1920, 1080, 4), (640, 360, 3)),
])
def test_frames_follow_rotation(cam, rotation, main_shape, lores_shape):
    img = np.zeros((1080, 1920, 4), np.uint8)
    img[0, 0] = 255                                 # top-left marker
    cam.set_rotation(rotation)
    main, lores = cam._frames(img)
    assert main.shape == main_shape and lores.shape == lores_shape
    if rotation == "inverted":
        assert main[-1, -1, 0] == 255


def test_any_camera_request_keeps_the_usb_camera(cam):
    cam.request_switch("noir")
    assert not cam._switch.is_set()


def test_find_device(tmp_path, monkeypatch):
    assert V.find_device("/dev/video4") == "/dev/video4"
    monkeypatch.setattr(V, "BY_ID", str(tmp_path / "*-video-index0"))
    assert V.find_device("auto") == "/dev/video0"
    (tmp_path / "usb-Cam_B-video-index0").touch()
    (tmp_path / "usb-Cam_A-video-index0").touch()
    assert V.find_device("auto").endswith("usb-Cam_A-video-index0")


def test_unplugged_camera_is_an_error_not_a_crash(cam, monkeypatch):
    def fail(device):
        cam.stop()
        raise OSError("cannot open /dev/video0")
    monkeypatch.setattr(cam, "_open", fail)
    cam.run()
    assert "USB camera" in cam.error and "cannot open" in cam.error
