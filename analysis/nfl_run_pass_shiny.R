# rsconnect::deployApp(
# appDir        = "C:/Users/c.travasos/Downloads/SBx",
# appName       = "nfl-run-pass-analysis",
# appFiles      = c("nfl_run_pass_shiny.R", "nfl_pbp.rda"),
# appPrimaryDoc = "nfl_run_pass_shiny.R"
# )


# ─────────────────────────────────────────────────────────────────────────────
# NFL Run/Pass Decision Analysis — Shiny App
# Team 1 = Offense | Team 2 = Defense
# Bars are stacked: Rush (secondary color) | Pass (primary color) = 100%
# Labels inside bars: current season% (prior 4-yr avg%)
# ─────────────────────────────────────────────────────────────────────────────

library(shiny)
library(shinyWidgets)
library(nflfastR)
library(ggplot2)
library(dplyr)

# ── Season Config ─────────────────────────────────────────────────────────────
current_season     <- 2026
historical_seasons <- (current_season - 4):current_season

# ── Data Loading ──────────────────────────────────────────────────────────────
load("nfl_pbp.rda")

# ── Bin Creation ──────────────────────────────────────────────────────────────
rp_plays <- pbp_nfl %>%
  mutate(
    distance_bin = factor(case_when(
      ydstogo <= 3  ~ "Short (1-3)",
      ydstogo <= 7  ~ "Medium (4-7)",
      ydstogo <= 10 ~ "Standard (8-10)",
      ydstogo > 10  ~ "Long (10+)"
    ), levels = c("Short (1-3)", "Medium (4-7)", "Standard (8-10)", "Long (10+)")),

    field_zone = factor(case_when(
      yardline_100 >= 80 ~ "Own Territory (0-20)",
      yardline_100 >= 51 ~ "Own Half (21-50)",
      yardline_100 >= 21 ~ "Opponent Half (51-79)",
      yardline_100 <= 20 ~ "Red Zone (1-20)"
    ), levels = c("Own Territory (0-20)", "Own Half (21-50)",
                  "Opponent Half (51-79)", "Red Zone (1-20)")),

    score_bin = factor(case_when(
      score_differential <= -21 ~ "Down 21+",
      score_differential <= -14 ~ "Down 14-20",
      score_differential <= -7  ~ "Down 7-13",
      score_differential <= -1  ~ "Down 1-6",
      score_differential == 0   ~ "Tied",
      score_differential <= 6   ~ "Up 1-6",
      score_differential <= 13  ~ "Up 7-13",
      score_differential <= 20  ~ "Up 14-20",
      score_differential >= 21  ~ "Up 21+"
    ), levels = c("Down 21+", "Down 14-20", "Down 7-13", "Down 1-6",
                  "Tied", "Up 1-6", "Up 7-13", "Up 14-20", "Up 21+"))
  )

# Drive context bins — only available after data is regenerated with new columns
drive_data_available   <- all(c("prev_own_drive_result", "prev_def_drive_result") %in% names(rp_plays))
time_data_available    <- "quarter_seconds_remaining" %in% names(rp_plays)
timeout_data_available <- "after_timeout" %in% names(rp_plays)

if (!timeout_data_available) {
  rp_plays <- rp_plays %>% mutate(after_timeout = FALSE)
}

drive_ctx_levels <- c("Passing TD", "Rushing TD", "FG Made", "FG Missed",
                      "Punt", "Interception", "Fumble", "Turnover on Downs", "Other")

if (drive_data_available) {
  rp_plays <- rp_plays %>%
    mutate(
      # Offensive context: what did this team's own previous drive end with?
      drive_context     = factor(prev_own_drive_result, levels = drive_ctx_levels),
      # Defensive context: what did the previous opponent do against this defteam?
      drive_context_def = factor(prev_def_drive_result, levels = drive_ctx_levels)
    )
} else {
  rp_plays <- rp_plays %>%
    mutate(drive_context     = NA_character_,
           drive_context_def = NA_character_,
           first_drive_play  = FALSE)
}

# ── Team Info ─────────────────────────────────────────────────────────────────
team_info <- nflfastR::teams_colors_logos

team_choices <- team_info %>%
  filter(team_abbr %in% unique(rp_plays$posteam)) %>%
  arrange(team_name) %>%
  { setNames(.$team_abbr, .$team_name) }

# ── Theme ─────────────────────────────────────────────────────────────────────
theme_nfl <- theme_minimal(base_size = 13) +
  theme(
    plot.title         = element_text(face = "bold", size = 14),
    plot.subtitle      = element_text(size = 10, color = "gray45"),
    axis.title         = element_text(size = 10),
    axis.text          = element_text(size = 9),
    legend.position    = "none",
    panel.grid.minor   = element_blank(),
    panel.grid.major.y = element_blank(),
    panel.grid.major.x = element_line(color = "gray90"),
    strip.text         = element_text(face = "bold", size = 11),
    strip.background   = element_rect(fill = "gray95", color = NA)
  )

season_label <- paste0(
  current_season, " Season  |  ",
  "Labels: ", current_season, "% (",
  min(historical_seasons), "–", max(historical_seasons), " avg%)"
)

# ── Helpers ───────────────────────────────────────────────────────────────────
get_team_info <- function(abbr) {
  row <- team_info %>% filter(team_abbr == abbr)
  list(
    name   = if (nrow(row) > 0) row$team_name[1]      else abbr,
    color  = if (nrow(row) > 0) row$team_color[1]     else "#333333",
    color2 = if (nrow(row) > 0) row$team_color2[1]    else "#888888",
    logo   = if (nrow(row) > 0) row$team_logo_espn[1] else NA_character_
  )
}

flip_score_bin <- function(df) {
  df %>% mutate(score_bin = factor(case_when(
    -score_differential <= -21 ~ "Down 21+",
    -score_differential <= -14 ~ "Down 14-20",
    -score_differential <= -7  ~ "Down 7-13",
    -score_differential <= -1  ~ "Down 1-6",
    -score_differential == 0   ~ "Tied",
    -score_differential <= 6   ~ "Up 1-6",
    -score_differential <= 13  ~ "Up 7-13",
    -score_differential <= 20  ~ "Up 14-20",
    -score_differential >= 21  ~ "Up 21+"
  ), levels = c("Down 21+", "Down 14-20", "Down 7-13", "Down 1-6",
                "Tied", "Up 1-6", "Up 7-13", "Up 14-20", "Up 21+")))
}

# Build long-format stacked data for a grouping variable
# Each row = one segment (pass or rush) per group per team side
make_stacked <- function(df, grp, side_label, ti) {
  curr <- df %>%
    filter(season == current_season) %>%
    group_by(across(all_of(grp))) %>%
    summarise(pass_curr = round(mean(play_type == "pass") * 100, 1), .groups = "drop") %>%
    mutate(rush_curr = 100 - pass_curr)

  hist <- df %>%
    filter(season %in% historical_seasons) %>%
    group_by(across(all_of(grp))) %>%
    summarise(pass_hist = round(mean(play_type == "pass") * 100, 1), .groups = "drop") %>%
    mutate(rush_hist = 100 - pass_hist)

  base <- curr %>% left_join(hist, by = grp)

  rush_rows <- base %>% mutate(
    play_type  = "rush",
    pct        = rush_curr,
    label      = paste0(rush_curr, "% (", rush_hist, "%)"),
    fill_color = ti$color2
  )
  pass_rows <- base %>% mutate(
    play_type  = "pass",
    pct        = pass_curr,
    label      = paste0(pass_curr, "% (", pass_hist, "%)"),
    fill_color = ti$color
  )

  bind_rows(pass_rows, rush_rows) %>%
    mutate(
      side      = side_label,
      play_type = factor(play_type, levels = c("pass", "rush"))
    )
}

# By-year stacked data (one bar per season, no historical comparison label)
make_by_season <- function(df, side_label, ti) {
  summ <- df %>%
    group_by(season) %>%
    summarise(pass_pct = round(mean(play_type == "pass") * 100, 1), .groups = "drop") %>%
    mutate(rush_pct = 100 - pass_pct)
  pass_rows <- summ %>% mutate(
    play_type  = "pass", pct = pass_pct,
    label      = paste0(pass_pct, "%"), fill_color = ti$color)
  rush_rows <- summ %>% mutate(
    play_type  = "rush", pct = rush_pct,
    label      = paste0(rush_pct, "%"), fill_color = ti$color2)
  bind_rows(pass_rows, rush_rows) %>%
    mutate(side = side_label, play_type = factor(play_type, levels = c("pass", "rush")))
}

# Stacked horizontal bar chart with Offense/Defense facets
stacked_bar_plot <- function(data, x, title, subtitle) {
  validate(need(nrow(data) > 0, "No data available for this view."))
  ggplot(data, aes(x = .data[[x]], y = pct, fill = fill_color, group = play_type)) +
    geom_col(position = "stack", width = 0.7) +
    geom_text(
      aes(label = label),
      position = position_stack(vjust = 0.5),
      size = 3.6, fontface = "bold", color = "white"
    ) +
    scale_fill_identity() +
    scale_y_continuous(limits = c(0, 100), expand = c(0, 0),
                       breaks = c(0, 25, 50, 75, 100)) +
    coord_flip() +
    facet_wrap(~ side, ncol = 1) +
    theme_nfl +
    labs(x = NULL, y = "% of Plays", title = title, subtitle = subtitle)
}

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- fluidPage(

  tags$head(tags$style(HTML("
    body  { font-family: 'Helvetica Neue', Arial, sans-serif; background: #f5f5f5; }
    .well { background: #ffffff; border: 1px solid #e0e0e0; border-radius: 8px; }
    h2    { font-weight: 700; margin-bottom: 4px; }
    .nav-tabs > li > a { font-weight: 600; }
    .team-role { font-size: 11px; color: gray; margin-top: -6px; margin-bottom: 10px; }
    .legend-swatch {
      display: inline-block; width: 14px; height: 14px;
      border-radius: 3px; margin-right: 5px; vertical-align: middle;
    }
    /* Sticky left sidebar — flex on the outer row unlocks sticky for floated children */
    .container-fluid > .row {
      display: -webkit-box;
      display: -ms-flexbox;
      display: flex;
      -webkit-box-align: start;
      -ms-flex-align: start;
      align-items: flex-start;
    }
    .container-fluid > .row > .col-sm-3 {
      position: -webkit-sticky;
      position: sticky;
      top: 10px;
      max-height: calc(100vh - 20px);
      overflow-y: auto;
    }
    /* Clear filters button */
    .btn-clear {
      width: 100%; font-size: 11px; color: #888;
      background: #f5f5f5; border: 1px solid #ddd;
      margin-top: 2px; margin-bottom: 8px;
    }
    .btn-clear:hover { background: #e8e8e8; color: #555; }
    /* Hide the Deselect All button in all picker dropdowns */
    .bs-deselect-all { display: none !important; }
  "))),

  titlePanel(
    div(h2("NFL Run/Pass Decision Analysis"),
        p(style = "color: gray; margin-top: -8px;", season_label)),
    windowTitle = "NFL Run/Pass Decision Analysis"
  ),

  sidebarLayout(
    sidebarPanel(
      width = 3,

      selectInput("team1", "Offense",
                  choices = team_choices, selected = "LV"),
      p(class = "team-role", "How they call plays"),

      selectInput("team2", "Defense",
                  choices = team_choices, selected = "LAC"),
      p(class = "team-role", "How opponents play against them"),

      hr(),
      uiOutput("team_legend"),

    ),

    mainPanel(
      width = 9,
      tabsetPanel(

        tabPanel("Split Overview",
          div(style = "margin-top: 20px;"),
          plotOutput("p_overall",  height = "260px"),
          hr(),
          plotOutput("p_by_down",  height = "400px"),
          hr(),
          plotOutput("p_by_dist",  height = "400px"),
          hr(),
          plotOutput("p_by_zone",  height = "400px"),
          hr(),
          plotOutput("p_by_score", height = "640px"),
          hr(),
          plotOutput("p_by_qtr",   height = "400px"),
          hr(),
          plotOutput("p_by_year",  height = "400px"),
          div(style = "margin-bottom: 30px;")
        ),

        tabPanel("Custom Filter",
          br(),
          fluidRow(
            column(3,
              wellPanel(
                h4("Situation Filters"),
                actionButton("clear_filters", "Clear All Filters", class = "btn-clear"),
                hr(),
                pickerInput("f_year", "Year",
                  choices  = setNames(historical_seasons, historical_seasons),
                  selected = historical_seasons,
                  multiple = TRUE,
                  options  = pickerOptions(actionsBox = TRUE, selectedTextFormat = "count > 1")),
                pickerInput("f_down", "Down",
                  choices  = c("1st"=1,"2nd"=2,"3rd"=3,"4th"=4),
                  selected = c(1,2,3,4),
                  multiple = TRUE,
                  options  = pickerOptions(actionsBox = TRUE, selectedTextFormat = "count > 1")),
                pickerInput("f_dist", "Distance",
                  choices  = c("Short (1-3)"     = "Short (1-3)",
                               "Medium (4-7)"    = "Medium (4-7)",
                               "Standard (8-10)" = "Standard (8-10)",
                               "Long (10+)"      = "Long (10+)"),
                  selected = c("Short (1-3)","Medium (4-7)","Standard (8-10)","Long (10+)"),
                  multiple = TRUE,
                  options  = pickerOptions(actionsBox = TRUE, selectedTextFormat = "count > 1")),
                pickerInput("f_field", "Field Position",
                  choices  = c("Own Territory (0-20)"  = "Own Territory (0-20)",
                               "Own Half (21-50)"      = "Own Half (21-50)",
                               "Opponent Half (51-79)" = "Opponent Half (51-79)",
                               "Red Zone (1-20)"      = "Red Zone (1-20)"),
                  selected = c("Own Territory (0-20)","Own Half (21-50)",
                               "Opponent Half (51-79)","Red Zone (1-20)"),
                  multiple = TRUE,
                  options  = pickerOptions(actionsBox = TRUE, selectedTextFormat = "count > 1")),
                pickerInput("f_score", "Score Differential",
                  choices  = c("Down 21+"  ="Down 21+",  "Down 14-20"="Down 14-20",
                               "Down 7-13" ="Down 7-13", "Down 1-6"  ="Down 1-6",
                               "Tied"      ="Tied",
                               "Up 1-6"   ="Up 1-6",    "Up 7-13"   ="Up 7-13",
                               "Up 14-20" ="Up 14-20",  "Up 21+"    ="Up 21+"),
                  selected = c("Down 21+","Down 14-20","Down 7-13","Down 1-6","Tied",
                               "Up 1-6","Up 7-13","Up 14-20","Up 21+"),
                  multiple = TRUE,
                  options  = pickerOptions(actionsBox = TRUE, selectedTextFormat = "count > 1")),
                pickerInput("f_qtr", "Quarter",
                  choices  = c("Q1"=1,"Q2"=2,"Q3"=3,"Q4"=4,"OT"=5),
                  selected = c(1,2,3,4,5),
                  multiple = TRUE,
                  options  = pickerOptions(actionsBox = TRUE, selectedTextFormat = "count > 1")),
                hr(),
                pickerInput("situation_type", "Special Situations",
                  choices  = c("First Play of Drive"       = "first_play",
                               "First Play After Timeout"  = "after_timeout",
                               "Under 2 Min in Half"       = "under_2min",
                               "All Other Plays"           = "other"),
                  selected = c("first_play","after_timeout","under_2min","other"),
                  multiple = TRUE,
                  options  = pickerOptions(actionsBox = TRUE, selectedTextFormat = "count > 1")),
                hr(),
                pickerInput("f_drive_ctx", "Previous Drive Ended With",
                  choices  = c("Passing TD"        = "Passing TD",
                               "Rushing TD"        = "Rushing TD",
                               "FG Made"           = "FG Made",
                               "FG Missed"         = "FG Missed",
                               "Punt"              = "Punt",
                               "Interception"      = "Interception",
                               "Fumble"            = "Fumble",
                               "Turnover on Downs" = "Turnover on Downs"),
                  selected = c("Passing TD","Rushing TD","FG Made","FG Missed",
                               "Punt","Interception","Fumble","Turnover on Downs"),
                  multiple = TRUE,
                  options  = pickerOptions(actionsBox = TRUE,
                                           selectedTextFormat = "count > 1"))
              )
            ),
            column(9,
              plotOutput("p_custom_curr", height = "260px"),
              uiOutput("custom_note"),
              br(),
              plotOutput("p_custom_hist", height = "260px")
            )
          )
        )

      )
    )
  )
)

# ── Server ────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  t1_plays <- reactive({ rp_plays %>% filter(posteam == input$team1) })
  t2_plays <- reactive({ rp_plays %>% filter(defteam == input$team2) %>% flip_score_bin() })

  t1_info  <- reactive({ get_team_info(input$team1) })
  t2_info  <- reactive({ get_team_info(input$team2) })
  matchup  <- reactive({
    paste0(t1_info()$name, " Offense  vs  ", t2_info()$name, " Defense")
  })

  # ── Sidebar legend ─────────────────────────────────────────────────────────
  output$team_legend <- renderUI({
    t1 <- t1_info()
    t2 <- t2_info()
    tags$div(
      # Offense
      tags$p(style = "font-size: 13px; font-weight: bold; margin-bottom: 1px;", t1$name),
      tags$p(style = "font-size: 11px; color: gray; margin-bottom: 5px; margin-top: 0;", "Offense"),
      tags$div(
        style = "display: flex; width: 100%; height: 26px; border-radius: 4px; overflow: hidden; margin-bottom: 14px;",
        tags$div(
          style = paste0("flex: 1; background:", t1$color2, "; display: flex; align-items: center; justify-content: center;"),
          tags$span(style = "color: white; font-size: 10px; font-weight: bold;", "Rush")
        ),
        tags$div(
          style = paste0("flex: 1; background:", t1$color, "; display: flex; align-items: center; justify-content: center;"),
          tags$span(style = "color: white; font-size: 10px; font-weight: bold;", "Pass")
        )
      ),
      # Defense
      tags$p(style = "font-size: 13px; font-weight: bold; margin-bottom: 1px;", t2$name),
      tags$p(style = "font-size: 11px; color: gray; margin-bottom: 5px; margin-top: 0;", "Defense"),
      tags$div(
        style = "display: flex; width: 100%; height: 26px; border-radius: 4px; overflow: hidden;",
        tags$div(
          style = paste0("flex: 1; background:", t2$color2, "; display: flex; align-items: center; justify-content: center;"),
          tags$span(style = "color: white; font-size: 10px; font-weight: bold;", "Rush")
        ),
        tags$div(
          style = paste0("flex: 1; background:", t2$color, "; display: flex; align-items: center; justify-content: center;"),
          tags$span(style = "color: white; font-size: 10px; font-weight: bold;", "Pass")
        )
      )
    )
  })

  # ── Overall ────────────────────────────────────────────────────────────────
  output$p_overall <- renderPlot({
    make_overall <- function(df, side_label, ti) {
      curr_pass <- round(mean(df$play_type[df$season == current_season] == "pass") * 100, 1)
      curr_rush <- 100 - curr_pass
      hist_pass <- round(mean(df$play_type[df$season %in% historical_seasons] == "pass") * 100, 1)
      hist_rush <- 100 - hist_pass
      tibble(
        side       = side_label,
        play_type  = factor(c("pass", "rush"), levels = c("pass", "rush")),
        pct        = c(curr_pass, curr_rush),
        label      = c(paste0(curr_pass, "% (", hist_pass, "%)"),
                       paste0(curr_rush, "% (", hist_rush, "%)")),
        fill_color = c(ti$color, ti$color2)
      )
    }

    data <- bind_rows(
      make_overall(t1_plays(), "Offense", t1_info()),
      make_overall(t2_plays(), "Defense", t2_info())
    ) %>% mutate(side = factor(side, levels = c("Defense", "Offense")))

    ggplot(data, aes(x = side, y = pct, fill = fill_color, group = play_type)) +
      geom_col(position = "stack", width = 0.5) +
      geom_text(aes(label = label),
                position = position_stack(vjust = 0.5),
                size = 4.2, fontface = "bold", color = "white") +
      scale_fill_identity() +
      scale_y_continuous(limits = c(0, 100), expand = c(0, 0),
                         breaks = c(0, 25, 50, 75, 100)) +
      coord_flip() +
      theme_nfl +
      labs(x = NULL, y = "% of Plays",
           title = "Overall",
           subtitle = matchup())
  })

  # ── By Down ────────────────────────────────────────────────────────────────
  output$p_by_down <- renderPlot({
    data <- bind_rows(
      make_stacked(t1_plays() %>% filter(down %in% 1:4), "down", "Offense", t1_info()),
      make_stacked(t2_plays() %>% filter(down %in% 1:4), "down", "Defense", t2_info())
    ) %>%
      mutate(side = factor(side, levels = c("Offense", "Defense")),
             down = factor(down, levels = 4:1,
                           labels = c("4th Down", "3rd Down", "2nd Down", "1st Down")))

    stacked_bar_plot(data, "down", "By Down", matchup())
  })

  # ── By Distance ────────────────────────────────────────────────────────────
  output$p_by_dist <- renderPlot({
    data <- bind_rows(
      make_stacked(t1_plays(), "distance_bin", "Offense", t1_info()),
      make_stacked(t2_plays(), "distance_bin", "Defense", t2_info())
    ) %>% mutate(side = factor(side, levels = c("Offense", "Defense")))

    stacked_bar_plot(data, "distance_bin", "By Distance", matchup())
  })

  # ── By Field Zone ──────────────────────────────────────────────────────────
  output$p_by_zone <- renderPlot({
    data <- bind_rows(
      make_stacked(t1_plays() %>% filter(!is.na(field_zone)), "field_zone", "Offense", t1_info()),
      make_stacked(t2_plays() %>% filter(!is.na(field_zone)), "field_zone", "Defense", t2_info())
    ) %>% mutate(side = factor(side, levels = c("Offense", "Defense")))

    stacked_bar_plot(data, "field_zone", "By Field Position", matchup())
  })

  # ── By Score ───────────────────────────────────────────────────────────────
  output$p_by_score <- renderPlot({
    data <- bind_rows(
      make_stacked(t1_plays() %>% filter(!is.na(score_bin)), "score_bin", "Offense", t1_info()),
      make_stacked(t2_plays() %>% filter(!is.na(score_bin)), "score_bin", "Defense", t2_info())
    ) %>% mutate(side = factor(side, levels = c("Offense", "Defense")))

    stacked_bar_plot(data, "score_bin", "By Score Differential", matchup())
  })

  # ── By Quarter ─────────────────────────────────────────────────────────────
  output$p_by_qtr <- renderPlot({
    data <- bind_rows(
      make_stacked(t1_plays() %>% filter(qtr %in% 1:4), "qtr", "Offense", t1_info()),
      make_stacked(t2_plays() %>% filter(qtr %in% 1:4), "qtr", "Defense", t2_info())
    ) %>%
      mutate(side = factor(side, levels = c("Offense", "Defense")),
             qtr  = factor(qtr, levels = 4:1,
                           labels = c("4th Quarter", "3rd Quarter", "2nd Quarter", "1st Quarter")))

    stacked_bar_plot(data, "qtr", "By Quarter", matchup())
  })

  # ── By Year ─────────────────────────────────────────────────────────────────
  output$p_by_year <- renderPlot({
    data <- bind_rows(
      make_by_season(t1_plays(), "Offense", t1_info()),
      make_by_season(t2_plays(), "Defense", t2_info())
    ) %>%
      mutate(
        side   = factor(side, levels = c("Offense", "Defense")),
        season = factor(season, levels = sort(unique(season)))
      )
    stacked_bar_plot(data, "season", "By Year", matchup())
  })

  # ── By Drive Context ────────────────────────────────────────────────────────
  # ── Custom Filter ──────────────────────────────────────────────────────────
  # ── Clear all filters ──────────────────────────────────────────────────────
  # Full choice sets — used to detect when a strict subset is selected
  all_f_years  <- as.character(historical_seasons)
  all_f_downs  <- c("1","2","3","4")
  all_f_dists  <- c("Short (1-3)","Medium (4-7)","Standard (8-10)","Long (10+)")
  all_f_fields <- c("Own Territory (0-20)","Own Half (21-50)","Opponent Half (51-79)","Red Zone (1-20)")
  all_f_scores <- c("Down 21+","Down 14-20","Down 7-13","Down 1-6","Tied","Up 1-6","Up 7-13","Up 14-20","Up 21+")
  all_f_qtrs   <- c("1","2","3","4","5")
  all_f_ctx    <- c("Passing TD","Rushing TD","FG Made","FG Missed",
                    "Punt","Interception","Fumble","Turnover on Downs")
  all_f_sits   <- c("first_play","after_timeout","under_2min","other")

  observeEvent(input$clear_filters, {
    updatePickerInput(session, "f_year",       selected = historical_seasons)
    updatePickerInput(session, "f_down",       selected = c(1,2,3,4))
    updatePickerInput(session, "f_dist",       selected = all_f_dists)
    updatePickerInput(session, "f_field",      selected = all_f_fields)
    updatePickerInput(session, "f_score",      selected = all_f_scores)
    updatePickerInput(session, "f_qtr",        selected = c(1,2,3,4,5))
    updatePickerInput(session, "situation_type", selected = all_f_sits)
    updatePickerInput(session, "f_drive_ctx",  selected = all_f_ctx)
  })

  # ── Dynamic title for the historical chart ──────────────────────────────────
  hist_title <- reactive({
    if (length(input$f_year) == 0) {
      paste0(min(historical_seasons), "\u2013", max(historical_seasons), " (All Seasons)")
    } else if (length(input$f_year) == 1) {
      paste0(input$f_year, " Season")
    } else {
      yrs <- sort(as.integer(input$f_year))
      paste0(min(yrs), "\u2013", max(yrs))
    }
  })

  # is_defense = TRUE   → filter on prev_def_drive_result (what last opponent did to Team B)
  # is_defense = FALSE  → filter on prev_own_drive_result (what Team A's own last drive ended with)
  # skip_year  = TRUE   → ignore f_year (used for the fixed 2025 chart so it always has data)
  # For picker filters that default to all-selected, only filter when a strict subset is chosen
  is_sub <- function(sel, all) length(sel) > 0 && length(sel) < length(all)

  apply_filters <- function(df, is_defense = FALSE, skip_year = FALSE) {
    if (!skip_year && is_sub(input$f_year,  all_f_years))
      df <- df %>% filter(season       %in% as.integer(input$f_year))
    if (is_sub(input$f_down,  all_f_downs))  df <- df %>% filter(down         %in% as.integer(input$f_down))
    if (is_sub(input$f_dist,  all_f_dists))  df <- df %>% filter(distance_bin %in% input$f_dist)
    if (is_sub(input$f_field, all_f_fields)) df <- df %>% filter(field_zone   %in% input$f_field)
    if (is_sub(input$f_score, all_f_scores)) df <- df %>% filter(score_bin    %in% input$f_score)
    if (is_sub(input$f_qtr,   all_f_qtrs))   df <- df %>% filter(qtr          %in% as.integer(input$f_qtr))
    # Special situations
    sits <- input$situation_type
    if (is_sub(sits, all_f_sits)) {
      if ("under_2min" %in% sits)
        validate(need(time_data_available,
          "Quarter-seconds data not available.\nPlease regenerate nfl_pbp.rda, then redeploy."))
      if ("after_timeout" %in% sits)
        validate(need(timeout_data_available,
          "Timeout data not available.\nPlease regenerate nfl_pbp.rda, then redeploy."))
      mask <- rep(FALSE, nrow(df))
      if ("first_play"    %in% sits) mask <- mask | (df$first_drive_play == TRUE)
      if ("after_timeout" %in% sits) mask <- mask | (df$after_timeout %in% TRUE)
      if ("under_2min"    %in% sits) mask <- mask | (df$qtr %in% c(2, 4) & df$quarter_seconds_remaining <= 120)
      if ("other" %in% sits) {
        other_mask <- df$first_drive_play != TRUE
        other_mask <- other_mask & !(df$after_timeout %in% TRUE)
        if (time_data_available)
          other_mask <- other_mask & !(df$qtr %in% c(2, 4) & df$quarter_seconds_remaining <= 120)
        mask <- mask | other_mask
      }
      df <- df[mask, ]
    }
    # Drive context — auto-restricts to first play of each drive
    if (is_sub(input$f_drive_ctx, all_f_ctx) && drive_data_available) {
      df <- df %>% filter(first_drive_play == TRUE)
      ctx_col <- if (is_defense) "drive_context_def" else "drive_context"
      df <- df %>% filter(.data[[ctx_col]] %in% input$f_drive_ctx)
    }
    df
  }

  # Shared helper — builds a filter label; only mentions filters where a strict subset is chosen
  sit_labels_map <- c("first_play"    = "First Play of Drive",
                      "after_timeout" = "First Play After Timeout",
                      "under_2min"    = "Under 2 Min in Half",
                      "other"         = "All Other Plays")
  make_filter_label <- function(include_year = TRUE) {
    parts <- c(
      if (include_year && is_sub(input$f_year,  all_f_years))  paste("Year:",     paste(input$f_year,                         collapse = "+")),
      if (is_sub(input$f_down,  all_f_downs))  paste("Down:",     paste(input$f_down,                                         collapse = "+")),
      if (is_sub(input$f_dist,  all_f_dists))  paste("Distance:", paste(input$f_dist,                                         collapse = "+")),
      if (is_sub(input$f_field, all_f_fields)) paste("Field:",    paste(input$f_field,                                        collapse = "+")),
      if (is_sub(input$f_score, all_f_scores)) paste("Score:",    paste(input$f_score,                                        collapse = "+")),
      if (is_sub(input$f_qtr,   all_f_qtrs))   paste("Quarter:",  paste(input$f_qtr,                                          collapse = "+")),
      if (is_sub(input$situation_type, all_f_sits)) paste("Situation:", paste(sit_labels_map[input$situation_type],            collapse = "+")),
      if (is_sub(input$f_drive_ctx,    all_f_ctx))  paste("Prev Drive:", paste(input$f_drive_ctx,                             collapse = "+"))
    )
    if (length(parts) == 0) "No filters applied" else paste(parts, collapse = " | ")
  }
  # curr chart ignores year filter, so don't mention it in the subtitle
  custom_label_curr <- reactive({ make_filter_label(include_year = FALSE) })
  custom_label      <- reactive({ make_filter_label(include_year = TRUE)  })

  make_custom_bars <- function(df, seasons_filter, side_label, ti) {
    d <- df %>% filter(season %in% seasons_filter)
    n <- nrow(d)
    pass_pct <- if (n > 0) round(mean(d$play_type == "pass") * 100, 1) else 0
    rush_pct <- 100 - pass_pct
    tibble(
      side       = side_label,
      play_type  = factor(c("pass", "rush"), levels = c("pass", "rush")),
      pct        = c(pass_pct, rush_pct),
      label      = c(paste0(pass_pct, "%\n(n=", n, ")"),
                     paste0(rush_pct, "%\n(n=", n, ")")),
      fill_color = c(ti$color, ti$color2)
    )
  }

  custom_chart <- function(data, title, subtitle) {
    validate(need(nrow(data) > 0, "No plays match this combination of filters."))
    ggplot(data, aes(x = side, y = pct, fill = fill_color, group = play_type)) +
      geom_col(position = "stack", width = 0.5) +
      geom_text(aes(label = label),
                position = position_stack(vjust = 0.5),
                size = 4.2, fontface = "bold", color = "white") +
      scale_fill_identity() +
      scale_y_continuous(limits = c(0, 100), expand = c(0, 0),
                         breaks = c(0, 25, 50, 75, 100)) +
      coord_flip() +
      theme_nfl +
      labs(x = NULL, y = "% of Plays", title = title, subtitle = subtitle)
  }

  output$p_custom_curr <- renderPlot({
    # skip_year = TRUE so the 2025 chart always has data regardless of year filter
    data <- bind_rows(
      make_custom_bars(apply_filters(t1_plays(), is_defense = FALSE, skip_year = TRUE), current_season, "Offense", t1_info()),
      make_custom_bars(apply_filters(t2_plays(), is_defense = TRUE,  skip_year = TRUE), current_season, "Defense", t2_info())
    ) %>% mutate(side = factor(side, levels = c("Defense", "Offense")))
    custom_chart(data, paste0(current_season, " Season"), custom_label_curr())
  })

  output$p_custom_hist <- renderPlot({
    data <- bind_rows(
      make_custom_bars(apply_filters(t1_plays(), is_defense = FALSE), historical_seasons, "Offense", t1_info()),
      make_custom_bars(apply_filters(t2_plays(), is_defense = TRUE),  historical_seasons, "Defense", t2_info())
    ) %>% mutate(side = factor(side, levels = c("Defense", "Offense")))
    custom_chart(data, hist_title(), custom_label())
  })

  output$custom_note <- renderUI({
    n1 <- nrow(apply_filters(t1_plays(), is_defense = FALSE, skip_year = TRUE) %>% filter(season == current_season))
    n2 <- nrow(apply_filters(t2_plays(), is_defense = TRUE,  skip_year = TRUE) %>% filter(season == current_season))
    msgs <- c()
    if (n1 < 10) msgs <- c(msgs, paste0(t1_info()$name, " OFF: only ", n1, " plays"))
    if (n2 < 10) msgs <- c(msgs, paste0(t2_info()$name, " DEF: only ", n2, " plays"))
    if (length(msgs) > 0) {
      div(style = "color: #e67e22; font-weight: bold;",
          paste("\u26a0 Small sample —", paste(msgs, collapse = "; ")))
    } else {
      div(style = "color: gray;",
          paste0(current_season, " — ",
                 t1_info()$name, " OFF: ", n1, "  |  ",
                 t2_info()$name, " DEF: ", n2))
    }
  })

}

shinyApp(ui, server)
