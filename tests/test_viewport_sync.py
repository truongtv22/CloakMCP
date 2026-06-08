"""Tests for fixed viewport to native window synchronization."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from cloakbrowsermcp.server import _do_sync_viewport_to_window


@pytest.mark.asyncio
async def test_sync_viewport_to_window_uses_outer_size_minus_chrome_height():
    mock_page = AsyncMock()
    mock_page.evaluate = AsyncMock(side_effect=[
        {"innerW": 1280, "innerH": 800, "outerW": 500, "outerH": 875},
        {"innerW": 500, "innerH": 800, "outerW": 500, "outerH": 875},
    ])
    mock_page.set_viewport_size = AsyncMock()

    mock_session = MagicMock()
    mock_session.get_page.return_value = mock_page

    with patch("cloakbrowsermcp.server._session", mock_session):
        result = await _do_sync_viewport_to_window("page_001")

    mock_page.set_viewport_size.assert_awaited_once_with({"width": 500, "height": 800})
    assert result["status"] == "viewport_synced"
    assert result["viewport"] == {"width": 500, "height": 800}


@pytest.mark.asyncio
async def test_sync_viewport_to_window_accepts_explicit_size():
    mock_page = AsyncMock()
    mock_page.evaluate = AsyncMock(side_effect=[
        {"innerW": 1280, "innerH": 800, "outerW": 500, "outerH": 875},
        {"innerW": 900, "innerH": 600, "outerW": 500, "outerH": 875},
    ])
    mock_page.set_viewport_size = AsyncMock()

    mock_session = MagicMock()
    mock_session.get_page.return_value = mock_page

    with patch("cloakbrowsermcp.server._session", mock_session):
        result = await _do_sync_viewport_to_window("page_001", width=900, height=600)

    mock_page.set_viewport_size.assert_awaited_once_with({"width": 900, "height": 600})
    assert result["viewport"] == {"width": 900, "height": 600}
