"""Download nflverse play-by-play and reduce it to one row per run/pass play with drive context.

This is a port of the data-generation chunk in analysis/nfl_run_pass_decisions.rmd: same filters,
same drive outcomes, same timeout and quarter-break flags.
"""
import numpy as np
import pandas as pd
import requests

from . import config

COLUMNS = [
    "game_id", "play_id", "season", "season_type", "posteam", "defteam", "drive", "play_type",
    "yards_gained", "down", "ydstogo", "yardline_100", "score_differential", "qtr",
    "quarter_seconds_remaining", "timeout", "pass_touchdown", "rush_touchdown",
    "field_goal_result", "interception", "fumble_lost", "fourth_down_failed",
]

DRIVE_OUTCOMES = ["Passing TD", "Rushing TD", "FG Made", "FG Missed", "Punt", "Interception",
                  "Fumble", "Turnover on Downs", "Other"]

PLAYS_FILE = config.PROCESSED / "plays.parquet"
TEAMS_FILE = config.RAW / "teams_colors_logos.csv"


def _download(url: str, path, force: bool) -> bool:
    """Fetch url into path unless it's already there. Returns False if the file doesn't exist upstream."""
    if path.exists() and not force:
        return True
    path.parent.mkdir(parents=True, exist_ok=True)
    print(f"  downloading {url}")
    resp = requests.get(url, timeout=300, stream=True)
    if resp.status_code == 404:
        return False
    resp.raise_for_status()
    tmp = path.with_suffix(path.suffix + ".part")
    with open(tmp, "wb") as f:
        for chunk in resp.iter_content(1 << 20):
            f.write(chunk)
    tmp.replace(path)
    return True


def _drive_outcomes(raw: pd.DataFrame) -> pd.DataFrame:
    """One row per (game, drive): who had the ball and how the drive ended."""
    flags = pd.DataFrame({
        "game_id": raw["game_id"],
        "drive": raw["drive"],
        "posteam": raw["posteam"],
        "defteam": raw["defteam"],
        "is_pass_td": raw["pass_touchdown"].eq(1),
        "is_rush_td": raw["rush_touchdown"].eq(1),
        "is_fg_made": raw["field_goal_result"].eq("made"),
        "is_fg_miss": raw["field_goal_result"].isin(["missed", "blocked"]),
        "is_punt": raw["play_type"].eq("punt"),
        "is_int": raw["interception"].eq(1),
        "is_fumble": raw["fumble_lost"].eq(1),
        "is_downs": raw["fourth_down_failed"].eq(1),
    })
    agg = {"posteam": "first", "defteam": "first"} | {c: "any" for c in flags.columns if c.startswith("is_")}
    drives = flags.groupby(["game_id", "drive"], dropna=False, sort=True).agg(agg).reset_index()
    # First matching outcome wins, in the same priority order as the R case_when
    conds = [drives[c] for c in ["is_pass_td", "is_rush_td", "is_fg_made", "is_fg_miss", "is_punt",
                                 "is_int", "is_fumble", "is_downs"]]
    drives["drive_outcome"] = np.select(conds, DRIVE_OUTCOMES[:-1], default="Other")
    drives = drives.sort_values(["game_id", "drive"], na_position="last")
    # Offense: how this offense's own previous drive ended
    drives["prev_own_drive_result"] = drives.groupby(["game_id", "posteam"])["drive_outcome"].shift()
    # Defense: how the previous drive against this defense ended
    drives["prev_def_drive_result"] = drives.groupby(["game_id", "defteam"])["drive_outcome"].shift()
    return drives[["game_id", "drive", "prev_own_drive_result", "prev_def_drive_result"]]


def _after_timeout_keys(raw: pd.DataFrame, rp: pd.DataFrame) -> set[tuple[str, float]]:
    """(game_id, play_id) of each team's first run/pass play after a timeout during its possession,
    plus its first run/pass play of Q2 and Q4 (the end-of-quarter breaks)."""
    index = rp[["game_id", "play_id", "posteam", "qtr"]].sort_values("play_id")
    timeouts = (raw.loc[raw["timeout"].fillna(0).eq(1), ["game_id", "play_id", "posteam"]]
                .rename(columns={"play_id": "timeout_play_id"}).sort_values("timeout_play_id"))
    nxt = pd.merge_asof(timeouts, index[["game_id", "play_id", "posteam"]],
                        left_on="timeout_play_id", right_on="play_id", by=["game_id", "posteam"],
                        direction="forward", allow_exact_matches=False).dropna(subset=["play_id"])
    keys = set(zip(nxt["game_id"], nxt["play_id"]))

    index = index.sort_values(["game_id", "play_id"])
    prev_qtr = index.groupby(["game_id", "posteam"])["qtr"].shift(fill_value=-1)
    brk = index[((index["qtr"] == 2) & (prev_qtr == 1)) | ((index["qtr"] == 4) & (prev_qtr == 3))]
    keys |= set(zip(brk["game_id"], brk["play_id"]))
    return keys


def process(raw: pd.DataFrame) -> pd.DataFrame:
    raw = raw[raw["season_type"].isin(["REG", "POST"]) & raw["posteam"].notna()]
    raw = raw.sort_values(["game_id", "play_id"]).reset_index(drop=True)

    drives = _drive_outcomes(raw)
    rp = raw[raw["play_type"].isin(["run", "pass"]) & raw["yards_gained"].notna()].copy()
    timeout_keys = _after_timeout_keys(raw, rp)

    rp["first_drive_play"] = rp.groupby(["game_id", "drive"], dropna=False).cumcount() == 0
    rp = rp.merge(drives, on=["game_id", "drive"], how="left")
    rp["after_timeout"] = [k in timeout_keys for k in zip(rp["game_id"], rp["play_id"])]
    return rp[["season", "play_type", "posteam", "defteam", "down", "ydstogo", "yardline_100",
               "score_differential", "qtr", "quarter_seconds_remaining", "first_drive_play",
               "after_timeout", "prev_own_drive_result", "prev_def_drive_result"]]


def update(all_seasons: bool = False) -> None:
    """Download missing seasons (and always the current one), then rebuild data/processed/plays.parquet."""
    seasons = config.seasons()
    current = seasons[-1]
    frames = []
    for season in seasons:
        path = config.RAW / f"play_by_play_{season}.parquet"
        found = _download(config.PBP_URL.format(season=season), path, force=all_seasons or season == current)
        if not found:
            print(f"  {season}: no play-by-play published yet, skipping")
            continue
        season_raw = pd.read_parquet(path, columns=COLUMNS)
        plays = process(season_raw)
        print(f"  {season}: {len(plays):,} run/pass plays")
        frames.append(plays)
    _download(config.TEAMS_URL, TEAMS_FILE, force=all_seasons)

    config.PROCESSED.mkdir(parents=True, exist_ok=True)
    pd.concat(frames, ignore_index=True).to_parquet(PLAYS_FILE, index=False)
    print(f"Saved {PLAYS_FILE.relative_to(config.ROOT)}")
