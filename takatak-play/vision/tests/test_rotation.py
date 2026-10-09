"""Camera picture rotation: frames turn right after capture; sizes follow."""
import numpy as np
import pytest

from takatak_vision.camera import ROTATIONS, rotate_frame, rotated_size
from takatak_vision.encoder import oriented
from takatak_vision import protocol as P


def marked_frame():
    """4 wide x 2 tall, 1 channel; the top-left pixel is marked."""
    img = np.zeros((2, 4, 1), dtype=np.uint8)
    img[0, 0, 0] = 255
    return img


@pytest.mark.parametrize("rotation,shape,mark", [
    ("normal", (2, 4, 1), (0, 0)),
    ("right", (4, 2, 1), (0, 1)),       # 90° clockwise: top-left → top-right
    ("inverted", (2, 4, 1), (1, 3)),    # 180°: top-left → bottom-right
    ("left", (4, 2, 1), (3, 0)),        # 90° counter-clockwise: top-left → bottom-left
])
def test_rotate_frame(rotation, shape, mark):
    out = rotate_frame(marked_frame(), rotation)
    assert out.shape == shape and out.flags.c_contiguous
    assert out[mark[0], mark[1], 0] == 255


def test_rotated_size():
    assert rotated_size((1920, 1080), "normal") == (1920, 1080)
    assert rotated_size((1920, 1080), "inverted") == (1920, 1080)
    assert rotated_size((1920, 1080), "right") == (1080, 1920)
    assert rotated_size((1920, 1080), "left") == (1080, 1920)
    with pytest.raises(KeyError):
        rotated_size((1, 1), "sideways")


def test_transport_size_follows_frame_shape():
    assert oriented((960, 540), np.zeros((1080, 1920, 4))) == (960, 540)
    assert oriented((960, 540), np.zeros((1920, 1080, 4))) == (540, 960)


def test_protocol_and_camera_agree_on_names():
    assert set(P.ROTATIONS) == set(ROTATIONS)
