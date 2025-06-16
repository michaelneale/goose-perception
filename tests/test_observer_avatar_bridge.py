import subprocess
from types import SimpleNamespace
from pathlib import Path
import sys

import pytest

# Ensure the package root is in path
ROOT_DIR = Path(__file__).resolve().parent.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from avatar.observer_avatar_bridge import ObserverAvatarBridge


class DummyAvatarDisplay:
    """Simple dummy avatar display to capture calls for assertions."""

    def __init__(self):
        self.shown_suggestions = []
        self.shown_actionable = []
        self.shown_messages = []

    def show_suggestion(self, _type, message):  # noqa: N802
        self.shown_suggestions.append(( _type, message))

    def show_actionable_message(self, message, action_data, avatar_state="pointing"):  # noqa: N802
        self.shown_actionable.append((message, action_data, avatar_state))

    def show_message(self, message, _timeout):  # noqa: N802
        self.shown_messages.append(message)

    # Qt helper placeholder
    def process_qt_events(self):
        pass


@pytest.fixture()
def patched_bridge(monkeypatch):
    """Return bridge instance with subprocess and avatar_display patched."""

    dummy_display = DummyAvatarDisplay()

    # Build a dummy avatar_display module that will be imported by bridge code
    import types, sys as _sys
    dummy_mod = types.ModuleType("avatar.avatar_display")
    dummy_mod.show_suggestion = dummy_display.show_suggestion
    dummy_mod.show_actionable_message = dummy_display.show_actionable_message
    dummy_mod.show_message = dummy_display.show_message
    dummy_mod.process_qt_events = dummy_display.process_qt_events

    # Register the dummy module so that `from . import avatar_display` resolves correctly
    _sys.modules["avatar.avatar_display"] = dummy_mod

    # Patch the already-imported bridge module's reference if it exists
    import avatar.observer_avatar_bridge as bridge_mod
    monkeypatch.setattr(bridge_mod, "avatar_display", dummy_mod, raising=False)

    # Helper to mock subprocess.run behaviour depending on recipe path
    def _mock_subprocess_run(cmd, capture_output, text, timeout, env):  # noqa: D401
        assert capture_output and text
        recipe_file = None
        for i, part in enumerate(cmd):
            if part == "--recipe" and i + 1 < len(cmd):
                recipe_file = cmd[i + 1]
                break
        # Default stdout / stderr
        stdout = ""
        if recipe_file and recipe_file.endswith("recipe-avatar-suggestions.yaml"):
            stdout = '{"suggestion": "Time for a stretch break!"}'
        elif recipe_file and recipe_file.endswith("recipe-actionable-suggestions.yaml"):
            stdout = (
                '{"actionable_suggestion": {"action_type": "email", "observation_type": "communication", '
                '"message": "Send a quick project update", "action_command": "compose_team_update"}}'
            )
        elif recipe_file and recipe_file.endswith("recipe-avatar-chatter.yaml"):
            stdout = "# Avatar Chit-Chat Message\n*Generated: 2025-06-15 12:00:00*\nHey there, coding superstar!"
        return subprocess.CompletedProcess(cmd, 0, stdout=stdout, stderr="")

    monkeypatch.setattr(subprocess, "run", _mock_subprocess_run)

    # Instantiate bridge with dummy model (doesn't matter here)
    bridge = ObserverAvatarBridge(goose_model="dummy-model")
    return bridge, dummy_display


def test_run_avatar_suggestions_shows_message(patched_bridge):
    bridge, dummy_display = patched_bridge

    bridge._run_avatar_suggestions()

    assert dummy_display.shown_suggestions, "No suggestion was shown"
    _type, message = dummy_display.shown_suggestions[-1]
    assert message == "Time for a stretch break!"


def test_run_actionable_suggestions_shows_actionable(patched_bridge):
    bridge, dummy_display = patched_bridge

    bridge._run_actionable_suggestions()

    assert dummy_display.shown_actionable, "No actionable suggestion was shown"
    message, action_data, _state = dummy_display.shown_actionable[-1]
    assert "project update" in message
    assert action_data["action_command"] == "compose_team_update"


def test_run_chatter_recipe_shows_message(patched_bridge):
    bridge, dummy_display = patched_bridge

    bridge._run_chatter_recipe()

    assert dummy_display.shown_messages, "No chatter message was shown"
    assert dummy_display.shown_messages[-1] == "Hey there, coding superstar!" 