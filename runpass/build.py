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


POSTSEASON = {"WC": "Wild Card", "DIV": "Divisional Round", "CON": "Conference Championships", "SB": "Super Bowl"}


def _text_on(hex_color: str) -> str:
    """White or near-black text, whichever reads better on the colour (same rule as app.js)."""
    n = int(hex_color.lstrip("#"), 16)
    lin = lambda v: v / 12.92 if (v := v / 255) <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    lum = 0.2126 * lin((n >> 16) & 255) + 0.7152 * lin((n >> 8) & 255) + 0.0722 * lin(n & 255)
    return "#111" if lum > 0.4 else "#fff"


def _split(plays: pd.DataFrame) -> dict:
    n = len(plays)
    pass_pct = round(plays["play_type"].eq("pass").mean() * 100, 1) if n else 0.0
    return {"n": n, "pass": pass_pct, "rush": round(100 - pass_pct, 1)}


def _fmt_time(hhmm: str) -> str:
    h, m = (int(x) for x in hhmm.split(":"))
    return f"{(h - 1) % 12 + 1}:{m:02d} {'AM' if h < 12 else 'PM'} ET"


def _this_week(plays: pd.DataFrame, teams: dict, current: int) -> dict | None:
    """The current season's earliest week with a game still to play (or its last week once the season
    is over), with each game's run/pass splits for both matchups."""
    if not data.SCHEDULE_FILE.exists():
        return None
    games = pd.read_csv(data.SCHEDULE_FILE)
    games = games[games["season"] == current]
    if games.empty:
        return None
    upcoming = games[games["result"].isna()]
    week = int(upcoming["week"].min() if len(upcoming) else games["week"].max())
    games = games[games["week"] == week].sort_values(["gameday", "gametime", "home_team"])

    cur = plays[plays["season"] == current]
    off = {t: _split(cur[cur["posteam"] == t]) for t in teams}
    off_h = {t: _split(plays[plays["posteam"] == t]) for t in teams}
    dfn = {t: _split(cur[cur["defteam"] == t]) for t in teams}
    dfn_h = {t: _split(plays[plays["defteam"] == t]) for t in teams}

    days = {}
    for g in games.itertuples():
        away, home = teams.get(g.away_team), teams.get(g.home_team)
        if away is None or home is None:
            continue
        line = None
        if pd.notna(g.spread_line) and g.spread_line != 0:
            fav = home if g.spread_line > 0 else away
            line = f"{fav['abbr']} −{abs(g.spread_line):g}"
        elif pd.notna(g.spread_line):
            line = "Pick'em"
        day = datetime.strptime(g.gameday, "%Y-%m-%d")
        days.setdefault(day, []).append({
            "away": away, "home": home,
            "time": _fmt_time(g.gametime) if isinstance(g.gametime, str) else "TBD",
            "final": pd.notna(g.result),
            "away_score": None if pd.isna(g.away_score) else int(g.away_score),
            "home_score": None if pd.isna(g.home_score) else int(g.home_score),
            "line": line,
            "total": None if pd.isna(g.total_line) else f"{g.total_line:g}",
            "matchups": [
                {"off": away, "def": home, "o": off[away["abbr"]], "oh": off_h[away["abbr"]],
                 "d": dfn[home["abbr"]], "dh": dfn_h[home["abbr"]]},
                {"off": home, "def": away, "o": off[home["abbr"]], "oh": off_h[home["abbr"]],
                 "d": dfn[away["abbr"]], "dh": dfn_h[away["abbr"]]},
            ],
        })
    first, last = min(days), max(days)
    span = f"{first:%b} {first.day}–{last.day}" if first.month == last.month else f"{first:%b} {first.day} – {last:%b} {last.day}"
    game_type = games["game_type"].iloc[0]
    return {
        "title": POSTSEASON.get(game_type, f"Week {week}"),
        "span": span,
        "days": [{"label": f"{d:%A}, {d:%b} {d.day}", "games": gs} for d, gs in sorted(days.items())],
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
    ctx = {"base": base, "updated": f"{now:%b} {now.day}, {now:%Y}", "meta": meta, "version": f"{now:%Y%m%d%H%M}",
           "season_range": f"{seasons[0]}–{seasons[-1]}", "current": seasons[-1],
           "n_plays": f"{len(plays):,}"}

    ctx["week"] = _this_week(plays, {t["abbr"]: t for t in teams}, seasons[-1])

    env = Environment(loader=FileSystemLoader(TEMPLATES), autoescape=True)
    env.filters["text_on"] = _text_on
    env.filters["pct"] = lambda v: f"{v:g}"
    for name, out in [("week.html", "index.html"), ("matchup.html", "matchup/index.html"),
                      ("about.html", "about/index.html")]:
        path = SITE / out
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(env.get_template(name).render(active=name.split(".")[0], **ctx), encoding="utf-8")
    print(f"Built {SITE.relative_to(config.ROOT)}: {len(teams)} teams, {len(plays):,} plays, seasons {seasons}")
