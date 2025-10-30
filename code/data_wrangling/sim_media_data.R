# ==============================================================================
# SIMULATE MEDIA SALIENCE DATA - Montreal Municipal Election 2025
# ==============================================================================
#
# This script simulates daily media salience indices (0-1) for each candidate
# and for the election overall. Data incorporates realistic trends based on
# polling trajectories and media event spikes (polls, debates).
#
# Structure: Wide format (1 row = 1 day, columns = candidates + election)
# Output: data/processed/media_salience_daily.rds
#
# Period: September 10, 2025 - November 1, 2025 (53 days)
#
# ==============================================================================

# Load libraries ---------------------------------------------------------------
library(tidyverse)
library(lubridate)

set.seed(2025)  # For reproducibility

# ==============================================================================
# PARAMETERS
# ==============================================================================

# Date range
start_date <- ymd("2025-09-10")
end_date <- ymd("2025-11-01")
dates <- seq(start_date, end_date, by = "day")
n_days <- length(dates)

# Candidates (from create_polls_dataset.R)
candidates <- c(
  "soraya_martinez_ferrada",
  "luc_rabouin",
  "craig_sauve",
  "gilbert_thibodeau",
  "jf_kacou",
  "indecis"
)

# ==============================================================================
# MEDIA EVENTS (for spikes in salience)
# ==============================================================================

# Polls release dates (salience spikes for "election" column)
poll_dates <- list(
  poll_1 = ymd("2025-09-15"):ymd("2025-09-21"),  # Léger poll 1
  poll_2 = ymd("2025-09-26"):ymd("2025-09-30"),  # Léger poll 2
  poll_3 = ymd("2025-10-03"):ymd("2025-10-09"),  # Segma poll
  poll_4 = ymd("2025-10-25")                     # Pallas poll
)

# Debates (major media events)
debate_dates <- c(
  ymd("2025-10-15"),  # First debate
  ymd("2025-10-20")   # Second debate
)

# Function to check if date is a media event
is_poll_period <- function(date) {
  date_num <- as.numeric(date)
  any(sapply(poll_dates, function(period) date_num %in% period))
}

is_debate_date <- function(date) {
  date %in% debate_dates
}

# ==============================================================================
# TREND FUNCTIONS BY CANDIDATE
# ==============================================================================

# Based on polling trajectories:
# Poll 1 (Sept 15-21): Martinez 20%, Rabouin 11%, Sauvé 6%, Thibodeau 5%, Kacou 2%, Indécis 48%
# Poll 2 (Sept 26-30): Martinez 21%, Rabouin 12%, Sauvé 8%, Thibodeau 7%, Kacou 2%, Indécis 42%
# Poll 3 (Oct 3-9):    Martinez 26%, Rabouin 18%, Sauvé 5%, Thibodeau 8%, Kacou 3%, Indécis 37%
# Poll 4 (Oct 25):     Martinez 33%, Rabouin 18%, Sauvé 6%, Thibodeau 11%, Kacou 3%, Indécis 29%

#' Generate baseline salience trend for Martinez Ferrada
#' Strong, consistent growth (front-runner momentum)
salience_martinez <- function(day_num) {
  # Linear growth from 0.30 to 0.60
  baseline <- 0.30 + (0.30 / n_days) * day_num

  # Extra boost after poll 3 (day 24: Oct 3) showing surge to 26%
  if (day_num >= 24) {
    baseline <- baseline + 0.08
  }

  # Extra boost after poll 4 (day 46: Oct 25) showing 33%
  if (day_num >= 46) {
    baseline <- baseline + 0.10
  }

  return(baseline)
}

#' Generate baseline salience trend for Rabouin
#' Growth then plateau (Projet Montréal fatigue sets in)
salience_rabouin <- function(day_num) {
  # Growth until Oct 10 (day 31), then plateau
  if (day_num <= 31) {
    baseline <- 0.20 + (0.15 / 31) * day_num  # 0.20 -> 0.35
  } else {
    baseline <- 0.35 + rnorm(1, 0, 0.02)  # Plateau with small noise
  }

  return(baseline)
}

#' Generate baseline salience trend for Sauvé
#' Stable/erratic, temporary spike mid-campaign
salience_sauve <- function(day_num) {
  baseline <- 0.15

  # Temporary spike around poll 2 (Sept 26-30, days 17-21) when he got 8%
  if (day_num >= 17 && day_num <= 25) {
    baseline <- baseline + 0.08
  }

  return(baseline)
}

#' Generate baseline salience trend for Thibodeau
#' Slow growth, late surge
salience_thibodeau <- function(day_num) {
  # Slow linear growth 0.12 -> 0.18 until Oct 20
  baseline <- 0.12 + (0.06 / 41) * min(day_num, 41)

  # Late surge after Oct 20 (day 41) leading to poll 4 showing 11%
  if (day_num >= 41) {
    baseline <- baseline + 0.07 + (day_num - 41) * 0.01
  }

  return(baseline)
}

#' Generate baseline salience trend for Kacou
#' Very low, stable (marginal candidate)
salience_kacou <- function(day_num) {
  baseline <- 0.06 + rnorm(1, 0, 0.01)  # Stable around 0.06
  return(baseline)
}

#' Generate baseline salience trend for Indécis
#' Strong decline as campaign progresses (voters decide)
salience_indecis <- function(day_num) {
  # Linear decline 0.50 -> 0.20
  baseline <- 0.50 - (0.30 / n_days) * day_num
  return(baseline)
}

#' Generate election overall salience
#' Grows as election approaches, spikes during polls/debates
salience_election <- function(date, day_num) {
  # Baseline growth: 0.30 -> 0.80 (exponential as election nears)
  days_to_election <- as.numeric(end_date - date)
  baseline <- 0.30 + 0.50 * (1 - days_to_election / n_days)^1.5

  # Spikes during poll periods
  if (is_poll_period(date)) {
    baseline <- baseline + 0.15
  }

  # Larger spikes during debates
  if (is_debate_date(date)) {
    baseline <- baseline + 0.25
  }

  # Final week: very high salience
  if (days_to_election <= 7) {
    baseline <- baseline + 0.15
  }

  return(baseline)
}

# ==============================================================================
# GENERATE DATA
# ==============================================================================

cat("Simulating media salience data...\n")
cat(sprintf("Period: %s to %s (%d days)\n", start_date, end_date, n_days))
cat(sprintf("Candidates: %d\n", length(candidates)))

# Initialize data frame
media_salience <- tibble(date = dates) %>%
  mutate(day_num = row_number() - 1)  # 0-indexed for easier math

# Generate salience for each candidate with realistic trends
media_salience <- media_salience %>%
  mutate(
    # Election overall salience
    election = map2_dbl(date, day_num, salience_election),

    # Each candidate with trend + noise
    soraya_martinez_ferrada = map_dbl(day_num, salience_martinez) + rnorm(n(), 0, 0.04),
    luc_rabouin = map_dbl(day_num, salience_rabouin) + rnorm(n(), 0, 0.04),
    craig_sauve = map_dbl(day_num, salience_sauve) + rnorm(n(), 0, 0.05),
    gilbert_thibodeau = map_dbl(day_num, salience_thibodeau) + rnorm(n(), 0, 0.03),
    jf_kacou = map_dbl(day_num, salience_kacou) + rnorm(n(), 0, 0.02),
    indecis = map_dbl(day_num, salience_indecis) + rnorm(n(), 0, 0.04)
  )

# Apply realistic constraints
media_salience <- media_salience %>%
  mutate(
    # Clamp all values to [0, 1]
    across(all_of(candidates), ~pmin(1, pmax(0, .x))),
    election = pmin(1, pmax(0, election)),

    # Ensure sum of candidate salience doesn't exceed election salience
    # (if election not salient, candidates can't be either)
    candidate_sum = soraya_martinez_ferrada + luc_rabouin + craig_sauve +
                    gilbert_thibodeau + jf_kacou + indecis,
    scale_factor = ifelse(candidate_sum > election, election / candidate_sum, 1),

    # Rescale candidates if needed
    across(all_of(candidates), ~.x * scale_factor)
  ) %>%
  select(-day_num, -candidate_sum, -scale_factor)

# Apply light smoothing for temporal autocorrelation (rolling average)
# Real media attention doesn't jump wildly day-to-day
media_salience <- media_salience %>%
  mutate(
    across(
      all_of(c(candidates, "election")),
      ~slider::slide_dbl(.x, mean, .before = 1, .after = 1, .complete = FALSE)
    )
  )

# ==============================================================================
# SUMMARY STATISTICS
# ==============================================================================

cat("\n=== SUMMARY STATISTICS ===\n\n")

# Overall statistics by candidate
cat("Salience by candidate (mean ± sd):\n")
media_salience %>%
  select(-date) %>%
  summarise(across(everything(), list(mean = mean, sd = sd))) %>%
  pivot_longer(everything(), names_to = c("variable", ".value"), names_sep = "_(?=[^_]+$)") %>%
  arrange(desc(mean)) %>%
  mutate(across(where(is.numeric), ~round(.x, 3))) %>%
  print()

# Trend validation: compare early vs late campaign
cat("\nEarly campaign (Sept 10-20) vs Late campaign (Oct 22-Nov 1):\n")
comparison <- media_salience %>%
  mutate(
    period = case_when(
      date <= ymd("2025-09-20") ~ "Early",
      date >= ymd("2025-10-22") ~ "Late",
      TRUE ~ "Mid"
    )
  ) %>%
  filter(period %in% c("Early", "Late")) %>%
  group_by(period) %>%
  summarise(across(all_of(candidates), mean)) %>%
  pivot_longer(-period, names_to = "candidate", values_to = "salience")

comparison %>%
  pivot_wider(names_from = period, values_from = salience) %>%
  mutate(
    change = Late - Early,
    pct_change = (Late - Early) / Early * 100
  ) %>%
  arrange(desc(change)) %>%
  mutate(across(where(is.numeric), ~round(.x, 3))) %>%
  print()

# Peak dates for election salience
cat("\nTop 5 dates for election salience:\n")
media_salience %>%
  arrange(desc(election)) %>%
  head(5) %>%
  select(date, election) %>%
  mutate(
    wday = wday(date, label = TRUE),
    election = round(election, 3)
  ) %>%
  print()

# ==============================================================================
# SAVE OUTPUT
# ==============================================================================

# Create output directory if needed
dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)

# Save as RDS (preserves types, compact)
output_path <- "data/processed/media_salience_daily.rds"
saveRDS(media_salience, output_path)

cat("\n✓ Data saved:", output_path, "\n")
cat(sprintf("  Dimensions: %d rows × %d columns\n", nrow(media_salience), ncol(media_salience)))
cat(sprintf("  File size: %.2f KB\n", file.size(output_path) / 1024))

# Also save as CSV for portability
output_csv <- "data/processed/media_salience_daily.csv"
write_csv(media_salience, output_csv)
cat(sprintf("✓ CSV saved: %s (%.2f KB)\n", output_csv, file.size(output_csv) / 1024))

cat("\n=== SIMULATION COMPLETE ===\n")
