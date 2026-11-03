import pytest


@pytest.fixture(autouse=True)
def _no_profile_env(monkeypatch):
    """TAKATAK_PROFILE set on the device (e.g. n150) must not change what the tests load."""
    monkeypatch.delenv("TAKATAK_PROFILE", raising=False)
