# NFL Run/Pass Tendencies

**Live site: [ctravasos.github.io/nfl-run-pass](https://ctravasos.github.io/nfl-run-pass/)**

Pick an offense and a defense and see how often the offense runs or passes, and how often opponents run or pass
against the defense, in every situation: down, distance, field position, score, quarter, season,
first play of a drive, after a timeout, the two-minute drill, and how the previous drive ended.
Every label compares this season with the five-season average. The site rebuilds itself every
morning from fresh nflverse play-by-play.

## Why

Play-calling tendencies are among the most useful facts in football analysis. A coordinator who almost
always passes on 3rd-and-medium, or a defense that teams run against when they're protecting a lead, tells
you what to expect next. The answer depends on both sides of the matchup, so the site puts the
offense's tendency next to what opponents do against the defense in the same situation.

## What's on the site

- **Split Overview**: run/pass splits by down, distance, field position, score differential, quarter and year,
  for the chosen offense and defense.
- **Custom Filter**: combine any filters (for example 1st down, trailing by 1–6, after the previous drive ended in a
  turnover) and compare this season with any range of the last five seasons. Small samples are flagged.

Matchups are shareable: the URL keeps the selected teams and tab (for example `#off=LV&def=LAC`).

## How it works

- **Data**: [nflverse](https://github.com/nflverse/nflverse-data) play-by-play, regular season and playoffs,
  run and pass plays only (sacks and scrambles count as passes).
- **Drive context**: each drive's outcome (passing TD, rushing TD, field goal made or missed, punt, interception,
  fumble, turnover on downs) is attached to the next drive: the offense's own previous drive, and the
  previous drive against the defense.
- **After timeout**: a team's first run or pass after a timeout during its possession, plus its first play after
  the end of the 1st and 3rd quarters.
- **Defense view**: score differential is from the defense's point of view, so "Up 7–13" means the defense's team
  was leading.

The pipeline writes one compact JSON file per team (about 40 KB compressed). The browser does all the
aggregation, so every filter combination works on a static host with no server.

## Tech

Python (pandas, pyarrow, requests) for the data pipeline, Jinja2 for the page shell, vanilla JS/CSS for the
charts, deployed with GitHub Actions to GitHub Pages twice a day.

| File | What it does |
|---|---|
| [`runpass/data.py`](runpass/data.py) | downloads play-by-play, computes drive outcomes and timeout flags, writes one row per run/pass play |
| [`runpass/build.py`](runpass/build.py) | writes the per-team JSON files and renders `templates/` into `site/` |
| [`runpass/config.py`](runpass/config.py) | seasons, data URLs, default matchup |
| [`static/js/app.js`](static/js/app.js) | bins, filters and charts in the browser |
| [`run.py`](run.py) | CLI: `update`, `build`, `serve` |
| [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) | scheduled rebuild and deploy |
| [`analysis/`](analysis/) | the original R Markdown analysis and the Shiny app this site replaces |

## Running locally

```bash
pip install -r requirements.txt
python run.py update     # first run downloads five seasons of play-by-play (~150 MB)
python run.py build      # renders the static site into site/
python run.py serve      # preview at http://localhost:8000
```

## Background

This started as an R analysis ([`analysis/nfl_run_pass_decisions.rmd`](analysis/nfl_run_pass_decisions.rmd)) and a
Shiny app ([`analysis/nfl_run_pass_shiny.R`](analysis/nfl_run_pass_shiny.R)). The Python pipeline is a direct port of
the R data step, checked against it: identical play counts and flags for 2024 and 2025.
