# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

library(tidyverse)
source("R/functions/model_functions.R")
source("R/functions/data_prep.R")

#' Calculer MAPE (Mean Absolute Percentage Error)
#'
#' @param actual Vecteur de valeurs réelles
#' @param predicted Vecteur de valeurs prédites
#' @return MAPE en pourcentage
calculate_mape <- function(actual, predicted) {
  mean(abs((actual - predicted) / actual), na.rm = TRUE) * 100
}


#' Calculer MAE (Mean Absolute Error)
#'
#' @param actual Vecteur de valeurs réelles
#' @param predicted Vecteur de valeurs prédites
#' @return MAE
calculate_mae <- function(actual, predicted) {
  mean(abs(actual - predicted), na.rm = TRUE)
}


#' Validation croisée temporelle: prédire un poll à partir d'un poll antérieur
#'
#' @param prior_poll_wave Numéro du poll prior
#' @param target_poll_wave Numéro du poll à prédire
#' @param polls Data frame polls
#' @param media_features Data frame média avec features
#' @param models Vecteur de noms de modèles à tester
#' @param params Liste de hyperparamètres par modèle
#' @return Tibble avec prédictions et actuals pour chaque candidat/modèle
validate_temporal <- function(prior_poll_wave, target_poll_wave,
                               polls, media_features,
                               models = c("baseline", "multiplicative", "bayesian", "delta"),
                               params = list()) {

  # Poll prior (input)
  prior_data <- prepare_model_data(polls, media_features, prior_poll_wave)

  # Poll target (actual outcome)
  target_data <- prepare_model_data(polls, media_features, target_poll_wave)

  # Média au moment du target (pour prédiction)
  target_date <- unique(target_data$date_poll_mid)
  media_at_target <- get_media_at_date(media_features, target_date, window_days = 7)

  # Média au moment du prior (pour delta)
  prior_date <- unique(prior_data$date_poll_mid)
  media_at_prior <- get_media_at_date(media_features, prior_date, window_days = 7)

  # Préparer data pour prédictions
  poll_input <- prior_data %>%
    select(candidat, vote_share) %>%
    left_join(media_at_target, by = "candidat") %>%
    mutate(momentum = replace_na(momentum, 0))

  # Actual (ground truth)
  actual <- target_data %>%
    select(candidat, vote_actual = vote_share)

  # Prédictions de chaque modèle
  results_list <- list()

  # Baseline: juste le poll prior
  results_list$baseline <- poll_input %>%
    select(candidat, prediction = vote_share)

  # Modèles hybrides
  if ("multiplicative" %in% models) {
    results_list$multiplicative <- predict_with_model(
      "multiplicative",
      poll_data = prior_data %>% select(candidat, vote_share),
      media_data = media_at_target,
      params = params$multiplicative
    )
  }

  if ("bayesian" %in% models) {
    results_list$bayesian <- predict_with_model(
      "bayesian",
      poll_data = prior_data %>% select(candidat, vote_share, sample_size),
      media_data = media_at_target,
      params = params$bayesian
    )
  }

  if ("delta" %in% models) {
    results_list$delta <- predict_with_model(
      "delta",
      poll_data = prior_data %>% select(candidat, vote_share),
      media_data = media_at_target,
      media_at_poll_data = media_at_prior,
      params = params$delta
    )
  }

  # Combiner résultats
  results <- results_list %>%
    bind_rows(.id = "model") %>%
    left_join(actual, by = "candidat") %>%
    mutate(
      prior_wave = prior_poll_wave,
      target_wave = target_poll_wave
    )

  return(results)
}


#' Valider sur plusieurs horizons temporels
#'
#' @param polls Data frame polls
#' @param media_features Data frame média avec features
#' @param test_pairs Liste de paires (prior, target) waves
#' @param models Modèles à tester
#' @param params Hyperparamètres
#' @return Tibble avec toutes les prédictions
validate_multiple_horizons <- function(polls, media_features,
                                        test_pairs = list(c(1, 2), c(2, 3), c(3, 4)),
                                        models = c("baseline", "multiplicative", "bayesian", "delta"),
                                        params = list()) {

  all_results <- map_df(test_pairs, function(pair) {
    prior_wave <- pair[1]
    target_wave <- pair[2]

    # Vérifier que les polls existent
    if (!(prior_wave %in% polls$poll_wave && target_wave %in% polls$poll_wave)) {
      return(NULL)
    }

    validate_temporal(prior_wave, target_wave, polls, media_features, models, params)
  })

  return(all_results)
}


#' Calculer métriques d'erreur par modèle et par test
#'
#' @param validation_results Output de validate_multiple_horizons()
#' @return Tibble avec MAPE/MAE par model + test
compute_validation_metrics <- function(validation_results) {

  # Par test individuel
  metrics_by_test <- validation_results %>%
    group_by(model, prior_wave, target_wave) %>%
    summarise(
      mape = calculate_mape(vote_actual, prediction),
      mae = calculate_mae(vote_actual, prediction),
      n_candidates = n(),
      .groups = "drop"
    )

  # Global (tous tests combinés)
  metrics_global <- validation_results %>%
    group_by(model) %>%
    summarise(
      mape_global = calculate_mape(vote_actual, prediction),
      mae_global = calculate_mae(vote_actual, prediction),
      n_obs = n(),
      .groups = "drop"
    )

  return(list(
    by_test = metrics_by_test,
    global = metrics_global
  ))
}
