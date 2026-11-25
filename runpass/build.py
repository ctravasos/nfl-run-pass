"""Render the static site: an app shell plus one compact JSON file of plays per team.

All aggregation happens in the browser (static/js/app.js), so every Custom Filter combination
works without a server.
"""
import json
import os
import shutil
from datetime import datetime, timezone

import pandas as pd
from jinja2 import Environment, FileSystemLoader

from . import config, data

SITE = config.ROOT / "site"
TEMPLATES = config.ROOT / "templates"
STATIC = config.ROOT / "static"

CTX_CODES = {name: i for i, name in enumerate(data.DRIVE_OUTCOMES)}


def _ints(series: pd.Series, missing: int = -1) -> list[int]:
    return series.fillna(missing).astype(int).tolist()


def _encode(plays: pd.DataFrame, side: str) -> dict:
    """Columnar arrays for one side of the ball. Defense rows are from the defense's point of view:
    the score differential is flipped, and drive context is how the previous drive against it ended."""
    sign = -1 if side == "d" else 1
    ctx_col = "prev_def_drive_result" if side == "d" else "prev_own_drive_result"
    return {
        "s": _ints(plays["season"]),
        "p": plays["play_type"].eq("pass").astype(int).tolist(),
        "dn": _ints(plays["down"], 0),
        "yt": _ints(plays["ydstogo"]),
        "yl": _ints(plays["yardline_100"]),
        "sd": _ints(plays["score_differential"] * sign, -999),
        "q": _ints(plays["qtr"]),
        "qs": _ints(plays["quarter_seconds_remaining"]),
        "f": plays["first_drive_play"].astype(int).tolist(),
        "t": plays["after_timeout"].astype(int).tolist(),
        "c": _ints(plays[ctx_col].map(CTX_CODES)),
    }


def build() -> None:
    plays = pd.read_parquet(data.PLAYS_FILE)
    seasons = sorted(int(s) for s in plays["season"].unique())[-config.N_SEASONS:]
    plays = plays[plays["season"].isin(seasons)]

    colors = pd.read_csv(data.TEAMS_FILE)
    active = set(plays["posteam"].dropna())
    teams = (colors[colors["team_abbr"].isin(active)]
             .sort_values("team_name")
             .apply(lambda r: {"abbr": r["team_abbr"], "name": r["team_name"], "nick": r["team_nick"],
                               "color": r["team_color"], "color2": r["team_color2"],
                               "logo": r["team_logo_espn"]}, axis=1)
             .tolist())

    if SITE.exists():
        shutil.rmtree(SITE)
    (SITE / "data" / "team").mkdir(parents=True)
    shutil.copytree(STATIC, SITE / "static")

    for t in teams:
        payload = {"o": _encode(plays[plays["posteam"] == t["abbr"]], "o"),
                   "d": _encode(plays[plays["defteam"] == t["abbr"]], "d")}
        (SITE / "data" / "team" / f"{t['abbr']}.json").write_text(json.dumps(payload, separators=(",", ":")))

    base = os.environ.get("SITE_BASE", "").rstrip("/")
    meta = {
        "base": base,
        "current": seasons[-1],
        "seasons": seasons,
        "contexts": data.DRIVE_OUTCOMES,
        "smallSample": config.SMALL_SAMPLE,
        "defaults": {"off": config.DEFAULT_OFFENSE, "def": config.DEFAULT_DEFENSE},
        "teams": teams,
    }
    now = datetime.now(timezone.utc)
    ctx = {"base": base, "updated": f"{now:%b} {now.day}, {now:%Y}", "meta": meta,
           "season_range": f"{seasons[0]}–{seasons[-1]}", "current": seasons[-1],
           "n_plays": f"{len(plays):,}"}

    env = Environment(loader=FileSystemLoader(TEMPLATES), autoescape=True)
    for name, out in [("index.html", "index.html"), ("about.html", "about/index.html")]:
        path = SITE / out
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(env.get_template(name).render(active=name.split(".")[0], **ctx), encoding="utf-8")
    print(f"Built {SITE.relative_to(config.ROOT)}: {len(teams)} teams, {len(plays):,} plays, seasons {seasons}")
