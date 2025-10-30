# ============================================================================
# PLOTTING FUNCTIONS
# ============================================================================

library(tidyverse)

#' Thème ggplot personnalisé avec fond blanc
#'
#' @return Thème ggplot2
theme_clean <- function() {
  theme_minimal() +
    theme(
      plot.background = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA),
      panel.grid.major = element_line(color = "gray90"),
      panel.grid.minor = element_line(color = "gray95"),
      legend.background = element_rect(fill = "white", color = NA),
      legend.key = element_rect(fill = "white", color = NA)
    )
}


#' Plot: Validation croisée temporelle (actual vs predicted)
#'
#' @param validation_results Output de validate_multiple_horizons()
#' @return ggplot object
plot_validation_scatter <- function(validation_results) {

  validation_results <- validation_results %>%
    mutate(
      model = factor(model,
                     levels = c("baseline", "multiplicative", "bayesian", "delta"),
                     labels = c("Baseline", "Multiplicatif", "Bayesian", "Delta")),
      test_label = paste0("Poll ", prior_wave, " → ", target_wave)
    )

  p <- ggplot(validation_results, aes(x = vote_actual, y = prediction,
                                       color = model, shape = model)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray50") +
    geom_point(size = 3, alpha = 0.7) +
    facet_wrap(~test_label) +
    scale_color_brewer(palette = "Set1") +
    labs(
      title = "Validation Croisée Temporelle: Actual vs Predicted",
      x = "Vote Share Actual",
      y = "Vote Share Predicted",
      color = "Model",
      shape = "Model"
    ) +
    theme_clean() +
    theme(legend.position = "bottom")

  return(p)
}


#' Plot: MAPE par test et modèle
#'
#' @param metrics Output de compute_validation_metrics()$by_test
#' @return ggplot object
plot_mape_by_test <- function(metrics) {

  metrics <- metrics %>%
    mutate(
      model = factor(model,
                     levels = c("baseline", "multiplicative", "bayesian", "delta"),
                     labels = c("Baseline", "Multiplicatif", "Bayesian", "Delta")),
      test_label = paste0("Poll ", prior_wave, " → ", target_wave)
    )

  p <- ggplot(metrics, aes(x = model, y = mape, fill = model)) +
    geom_col() +
    geom_text(aes(label = sprintf("%.1f%%", mape)), vjust = -0.5, size = 3.5) +
    facet_wrap(~test_label) +
    scale_fill_brewer(palette = "Set1") +
    labs(
      title = "MAPE par Test et Modèle",
      subtitle = "Lower is better",
      x = NULL,
      y = "Mean Absolute Percentage Error (%)"
    ) +
    theme_clean() +
    theme(
      legend.position = "none",
      axis.text.x = element_text(angle = 45, hjust = 1)
    )

  return(p)
}


#' Plot: MAPE global (barchart avec amélioration vs baseline)
#'
#' @param metrics Output de compute_validation_metrics()$global
#' @return ggplot object
plot_mape_global <- function(metrics) {

  baseline_mape <- metrics %>% filter(model == "baseline") %>% pull(mape_global)

  metrics <- metrics %>%
    mutate(
      model = factor(model,
                     levels = c("baseline", "multiplicative", "bayesian", "delta"),
                     labels = c("Baseline", "Multiplicatif", "Bayesian", "Delta")),
      improvement = baseline_mape - mape_global,
      better = improvement > 0
    )

  p <- ggplot(metrics, aes(x = model, y = mape_global, fill = better)) +
    geom_col() +
    geom_text(aes(label = sprintf("%.1f%%", mape_global)), vjust = -0.5, size = 4) +
    scale_fill_manual(values = c("TRUE" = "#4CAF50", "FALSE" = "#F44336"),
                      labels = c("Pire que baseline", "Meilleur que baseline")) +
    labs(
      title = "MAPE Global par Modèle",
      subtitle = "Moyenne sur tous les tests de validation",
      x = NULL,
      y = "Mean Absolute Percentage Error (%)",
      fill = "Performance"
    ) +
    theme_clean() +
    theme(legend.position = "bottom")

  return(p)
}


#' Plot: Forecast final (barplot comparant modèles)
#'
#' @param forecast_data Tibble avec candidat + forecast par modèle
#' @param election_date Date de l'élection
#' @param last_poll_wave Numéro du dernier poll utilisé
#' @return ggplot object
plot_final_forecast <- function(forecast_data, election_date, last_poll_wave) {

  forecast_long <- forecast_data %>%
    pivot_longer(
      cols = starts_with("forecast_"),
      names_to = "model",
      values_to = "forecast",
      names_prefix = "forecast_"
    ) %>%
    mutate(
      model = factor(model,
                     levels = c("baseline", "multiplicative", "bayesian", "delta"),
                     labels = c("Baseline", "Multiplicatif", "Bayesian", "Delta"))
    )

  p <- ggplot(forecast_long, aes(x = candidat, y = forecast, fill = model)) +
    geom_col(position = "dodge") +
    scale_fill_brewer(palette = "Set1") +
    scale_y_continuous(labels = scales::percent_format()) +
    labs(
      title = paste0("Forecast Final Élection Montréal (", format(election_date, "%d %b %Y"), ")"),
      subtitle = paste0("Basé sur poll ", last_poll_wave, " + données média"),
      x = "Candidat",
      y = "Vote Share Forecasted",
      fill = "Model"
    ) +
    theme_clean() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  return(p)
}


#' Plot: Évolution temporelle saillance média
#'
#' @param media_features Output de compute_media_features()
#' @param polls Pour annoter dates des sondages
#' @return ggplot object
plot_media_timeline <- function(media_features, polls = NULL) {

  p <- ggplot(media_features, aes(x = date, y = salience_share, color = candidat)) +
    geom_line(alpha = 0.7) +
    scale_color_brewer(palette = "Set1") +
    scale_y_continuous(labels = scales::percent_format()) +
    labs(
      title = "Évolution de la Saillance Média par Candidat",
      x = "Date",
      y = "Saillance Share (% couverture quotidienne)",
      color = "Candidat"
    ) +
    theme_clean()

  # Annoter dates de polls si fourni
  if (!is.null(polls)) {
    poll_dates <- polls %>%
      distinct(poll_wave, date_poll_mid) %>%
      filter(!is.na(poll_wave))

    p <- p + geom_vline(data = poll_dates, aes(xintercept = date_poll_mid),
                        linetype = "dashed", color = "gray40", alpha = 0.5) +
      geom_text(data = poll_dates,
                aes(x = date_poll_mid, y = Inf, label = paste0("Poll ", poll_wave)),
                angle = 90, vjust = -0.5, hjust = 1, size = 3, color = "gray30")
  }

  return(p)
}


#' Plot: Table de résultats finale (gt table)
#'
#' @param forecast_data Tibble avec forecasts
#' @param metrics Métriques de validation
#' @return gt table object (nécessite library(gt))
create_results_table <- function(forecast_data, metrics) {
  # TODO: implémenter avec gt si nécessaire
  # Pour l'instant, retourne un tibble formaté
  forecast_data %>%
    mutate(across(where(is.numeric), ~round(.x * 100, 1))) %>%
    arrange(desc(forecast_baseline))
}
