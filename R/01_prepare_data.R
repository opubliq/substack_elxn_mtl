# ============================================================================
# 01: PRÉPARATION DES DONNÉES
# ============================================================================
# Charge et prépare les données polls + média avec features engineerées
# Output: data/processed/model_data.rds

library(tidyverse)
source("R/functions/data_prep.R")

cat("=== 01: DATA PREPARATION ===\n\n")

# ----------------------------------------------------------------------------
# 1. Charger données brutes
# ----------------------------------------------------------------------------

cat("Loading raw data...\n")
polls <- load_polls("data/processed/polls.rds")
media <- load_media("data/processed/media_salience_daily.csv")

cat("  Polls:", nrow(polls), "rows,", n_distinct(polls$poll_wave), "waves\n")
cat("  Media:", nrow(media), "rows,", n_distinct(media$date), "days\n")

# Vérifier présence indécis
indecis_check <- polls %>% filter(candidat == "indecis")
cat("  Indécis présents:", nrow(indecis_check) > 0, "\n")

if (nrow(indecis_check) > 0) {
  indecis_summary <- indecis_check %>%
    group_by(poll_wave) %>%
    summarise(pct_indecis = mean(vote_intention) * 100, .groups = "drop")

  cat("\n  % Indécis par poll:\n")
  print(indecis_summary)
}

# ----------------------------------------------------------------------------
# 2. Calculer features média
# ----------------------------------------------------------------------------

cat("\nComputing media features...\n")
media_features <- compute_media_features(media)

cat("  Features calculés: salience_share, momentum, salience_ma7\n")

# Vérifier qualité des features
feature_summary <- media_features %>%
  filter(date >= max(date) - 7) %>%  # Dernière semaine
  group_by(candidat) %>%
  summarise(
    salience_mean = mean(salience_share, na.rm = TRUE),
    momentum_mean = mean(momentum, na.rm = TRUE),
    .groups = "drop"
  )

cat("\n  Dernière semaine - saillance moyenne:\n")
print(feature_summary %>% arrange(desc(salience_mean)), n = Inf)

# ----------------------------------------------------------------------------
# 3. Préparer données par poll wave (pour modélisation)
# ----------------------------------------------------------------------------

cat("\nPreparing model data by poll wave...\n")

available_polls <- polls %>%
  filter(!is.na(poll_wave)) %>%
  distinct(poll_wave) %>%
  pull(poll_wave) %>%
  sort()

cat("  Available poll waves:", paste(available_polls, collapse = ", "), "\n")

model_data_by_wave <- map(available_polls, function(wave) {
  prepare_model_data(polls, media_features, poll_wave = wave)
})

names(model_data_by_wave) <- paste0("poll_", available_polls)

# Aperçu
cat("\n  Sample model data (poll 1):\n")
print(model_data_by_wave$poll_1 %>% select(candidat, vote_share, salience_share, momentum))

# ----------------------------------------------------------------------------
# 4. Sauvegarder données préparées
# ----------------------------------------------------------------------------

cat("\nSaving prepared data...\n")

output_data <- list(
  polls = polls,
  media_features = media_features,
  model_data_by_wave = model_data_by_wave,
  metadata = list(
    date_prepared = Sys.time(),
    n_polls = length(available_polls),
    date_range_media = range(media$date),
    has_indecis = nrow(indecis_check) > 0
  )
)

saveRDS(output_data, "data/processed/model_data.rds")

cat("  Saved to: data/processed/model_data.rds\n")

cat("\n=== DATA PREPARATION COMPLETE ===\n")
