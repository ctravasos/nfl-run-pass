"""Seasons, paths and data sources."""
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
PROCESSED = ROOT / "data" / "processed"

# Current season plus the prior four. Each chart label reads "current% (5-season avg%)", and the
# five-season average includes the current season, as in the original analysis.
N_SEASONS = 5

PBP_URL = "https://github.com/nflverse/nflverse-data/releases/download/pbp/play_by_play_{season}.parquet"
TEAMS_URL = "https://github.com/nflverse/nflverse-data/releases/download/teams/teams_colors_logos.csv"

DEFAULT_OFFENSE = "LV"
DEFAULT_DEFENSE = "LAC"

# Fewer current-season plays than this in a Custom Filter view gets a small-sample warning.
SMALL_SAMPLE = 10


def current_season(today: date | None = None) -> int:
    """NFL seasons are named for the year they start in; before September we're in the offseason."""
    today = today or date.today()
    return today.year if today.month >= 9 else today.year - 1


def seasons() -> list[int]:
    cur = current_season()
    return list(range(cur - N_SEASONS + 1, cur + 1))
