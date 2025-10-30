# ============================================================================
# DATA PREPARATION FUNCTIONS
# ============================================================================

library(tidyverse)
library(slider)

#' Charger et nettoyer les données de sondage
#'
#' IMPORTANT: Garde les indécis comme catégorie
#'
#' @param path Chemin vers polls.rds
#' @return Tibble avec: poll_id, poll_wave, candidat, vote_intention, date_*, sample_size
load_polls <- function(path = "data/processed/polls.rds") {
  polls_raw <- readRDS(path)

  polls <- polls_raw %>%
    select(poll_id, candidat, vote_intention, date_debut, date_fin, sample_size) %>%
    mutate(
      poll_wave = case_when(
        poll_id == "poll_1" ~ 1,
        poll_id == "poll_2" ~ 2,
        poll_id == "poll_3" ~ 3,
        poll_id == "poll_4" ~ 4,
        TRUE ~ NA_real_
      ),
      date_poll_mid = date_debut + (date_fin - date_debut) / 2
    ) %>%
    filter(!is.na(poll_wave))  # Exclure polls sans wave assignée

  return(polls)
}


#' Charger et nettoyer les données média
#'
#' @param path Chemin vers media_salience_daily.csv
#' @return Tibble avec: date, candidat, salience_raw, election
load_media <- function(path = "data/processed/media_salience_daily.csv") {
  media_raw <- read_csv(path, show_col_types = FALSE)

  media <- media_raw %>%
    pivot_longer(
      cols = c(soraya_martinez_ferrada, luc_rabouin, craig_sauve,
               gilbert_thibodeau, jf_kacou, indecis),
      names_to = "candidat_raw",
      values_to = "salience_raw"
    ) %>%
    mutate(
      candidat = candidat_raw  # Garde noms tels quels pour matching
    ) %>%
    select(date, candidat, salience_raw, election)

  return(media)
}


#' Calculer features média (salience share, momentum, moving averages)
#'
#' @param media_data Output de load_media()
#' @return Tibble enrichi avec salience_share, momentum, salience_ma7
compute_media_features <- function(media_data) {

  media_features <- media_data %>%
    group_by(date) %>%
    mutate(
      salience_total_day = sum(salience_raw),
      salience_share = salience_raw / salience_total_day  # Relative (sum-to-1 par jour)
    ) %>%
    ungroup() %>%
    arrange(candidat, date) %>%
    group_by(candidat) %>%
    mutate(
      # Momentum: différence entre moyenne 3 derniers jours vs 4 jours avant
      salience_recent_3d = slide_dbl(salience_share, mean, .before = 2, .complete = TRUE),
      salience_baseline_4d = slide_dbl(salience_share, mean, .before = 6, .after = -3, .complete = TRUE),
      momentum = salience_recent_3d - salience_baseline_4d,

      # Moyenne mobile 7 jours (lisse le bruit)
      salience_ma7 = slide_dbl(salience_share, mean, .before = 6, .complete = TRUE)
    ) %>%
    ungroup()

  return(media_features)
}


#' Extraire saillance média à une date donnée (agrégée sur fenêtre)
#'
#' @param media_features Output de compute_media_features()
#' @param target_date Date cible
#' @param window_days Fenêtre de temps (jours avant target_date)
#' @return Tibble avec: candidat, salience_share_avg, momentum_avg, ...
get_media_at_date <- function(media_features, target_date, window_days = 7) {

  media_at_date <- media_features %>%
    filter(date <= target_date, date > target_date - window_days) %>%
    group_by(candidat) %>%
    summarise(
      salience_share = mean(salience_share, na.rm = TRUE),
      salience_ma7 = mean(salience_ma7, na.rm = TRUE),
      momentum = mean(momentum, na.rm = TRUE),
      n_days = n(),
      .groups = "drop"
    )

  return(media_at_date)
}


#' Préparer données pour modélisation: poll + média au même timestamp
#'
#' @param polls Output de load_polls()
#' @param media_features Output de compute_media_features()
#' @param poll_wave Numéro du poll à extraire
#' @param media_window_days Fenêtre pour agrégation média
#' @return Tibble avec: candidat, vote_share, salience_share, momentum, ...
prepare_model_data <- function(polls, media_features, poll_wave, media_window_days = 7) {

  # Extraire poll
  poll_data <- polls %>%
    filter(poll_wave == !!poll_wave) %>%
    select(candidat, vote_intention, date_poll_mid, sample_size)

  if (nrow(poll_data) == 0) {
    stop("No data for poll_wave = ", poll_wave)
  }

  # Date du poll (pour matching média)
  poll_date <- unique(poll_data$date_poll_mid)

  # Média à cette date
  media_at_poll <- get_media_at_date(media_features, poll_date, media_window_days)

  # Combiner
  model_data <- poll_data %>%
    left_join(media_at_poll, by = "candidat") %>%
    mutate(
      vote_share = vote_intention,  # Alias pour clarté
      momentum = replace_na(momentum, 0)  # Remplacer NA momentum par 0
    )

  return(model_data)
}


#' Réallouer indécis proportionnellement aux candidats décidés
#'
#' Utile pour comparer poll vs prédiction sur même base
#'
#' @param data Tibble avec candidat + vote_share (incluant indecis)
#' @return Tibble avec vote_share_decided (sans indécis, renormalisé)
reallocate_undecided <- function(data) {

  # Séparer indécis du reste
  decided <- data %>% filter(candidat != "indecis")
  undecided_pct <- data %>% filter(candidat == "indecis") %>% pull(vote_share)

  if (length(undecided_pct) == 0) {
    undecided_pct <- 0
  }

  # Réallouer proportionnellement
  decided_total <- sum(decided$vote_share)
  decided <- decided %>%
    mutate(
      vote_share_decided = vote_share + (vote_share / decided_total) * undecided_pct
    )

  return(decided)
}
