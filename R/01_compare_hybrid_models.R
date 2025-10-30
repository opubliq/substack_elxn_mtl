# ============================================================================
# Comparaison de 3 Approches de Combinaison Saillance + Polls
# ============================================================================
# Objectif: Tester empiriquement différentes mécaniques de fusion poll/média
# Validation:
#   - Train poll 1 → predict poll 2
#   - Train polls 1+2 → predict poll 3
#   - Train polls 1+2+3 → predict poll 4
#   - Train ALL polls → predict election result

library(tidyverse)
library(slider)

# ============================================================================
# 1. CHARGEMENT DES DONNÉES
# ============================================================================

# Polls
polls_raw <- readRDS("data/processed/polls.rds")

# Media salience
media_raw <- read_csv("data/processed/media_salience_daily.csv", show_col_types = FALSE)

# ============================================================================
# 2. PRÉPARATION DES DONNÉES
# ============================================================================

# Restructurer polls en format wide
polls <- polls_raw %>%
  filter(candidat != "indecis") %>%  # exclure indécis pour l'instant
  select(poll_id, candidat, vote_intention, date_debut, date_fin, sample_size) %>%
  mutate(
    poll_wave = case_when(
      poll_id == "poll_1" ~ 1,
      poll_id == "poll_2" ~ 2,
      poll_id == "poll_3" ~ 3
    ),
    date_poll = date_fin  # utiliser date de fin du sondage
  )

# Calculer date médiane du poll pour matching avec média
polls <- polls %>%
  mutate(date_poll_mid = date_debut + (date_fin - date_debut) / 2)

cat("\n=== POLLS STRUCTURE ===\n")
polls %>%
  group_by(poll_wave, date_debut, date_fin) %>%
  summarise(n_candidates = n(), .groups = "drop") %>%
  print()

# Restructurer media (déjà en format long par jour)
# Normaliser noms de colonnes candidats
media <- media_raw %>%
  pivot_longer(
    cols = c(soraya_martinez_ferrada, luc_rabouin, craig_sauve,
             gilbert_thibodeau, jf_kacou),
    names_to = "candidat_raw",
    values_to = "salience_raw"
  ) %>%
  mutate(
    # Standardiser noms candidats pour matching avec polls
    candidat = case_when(
      candidat_raw == "soraya_martinez_ferrada" ~ "soraya_martinez_ferrada",
      candidat_raw == "luc_rabouin" ~ "luc_rabouin",
      candidat_raw == "craig_sauve" ~ "craig_sauve",
      candidat_raw == "gilbert_thibodeau" ~ "gilbert_thibodeau",
      candidat_raw == "jf_kacou" ~ "jf_kacou"
    )
  ) %>%
  select(date, candidat, salience_raw, election)

cat("\n=== MEDIA DATA RANGE ===\n")
cat("Start:", as.character(min(media$date)), "\n")
cat("End:", as.character(max(media$date)), "\n")
cat("N days:", n_distinct(media$date), "\n")

# ============================================================================
# 3. FEATURE ENGINEERING: MEDIA METRICS
# ============================================================================

# Calculer salience share (relative) par jour
media_features <- media %>%
  group_by(date) %>%
  mutate(
    salience_total_day = sum(salience_raw),
    salience_share = salience_raw / salience_total_day  # sum-to-1 par jour
  ) %>%
  ungroup() %>%
  arrange(candidat, date) %>%
  group_by(candidat) %>%
  mutate(
    # Momentum: différence entre moyenne 3 derniers jours vs 4 jours avant
    salience_recent_3d = slide_dbl(salience_share, mean, .before = 2, .complete = TRUE),
    salience_baseline_4d = slide_dbl(salience_share, mean, .before = 6, .after = -3, .complete = TRUE),
    momentum = salience_recent_3d - salience_baseline_4d,

    # Moyenne mobile 7 jours (pour stabiliser signal)
    salience_ma7 = slide_dbl(salience_share, mean, .before = 6, .complete = TRUE)
  ) %>%
  ungroup()

cat("\n=== MEDIA FEATURES SAMPLE ===\n")
media_features %>%
  filter(date >= as.Date("2025-10-25")) %>%
  select(date, candidat, salience_share, momentum, salience_ma7) %>%
  print(n = 10)

# ============================================================================
# 4. FONCTION: EXTRAIRE MÉDIA À UNE DATE DONNÉE
# ============================================================================

get_media_at_date <- function(target_date, window_days = 7) {
  # Extrait salience moyenne sur fenêtre window_days AVANT target_date
  media_features %>%
    filter(date <= target_date, date > target_date - window_days) %>%
    group_by(candidat) %>%
    summarise(
      salience_share_avg = mean(salience_share, na.rm = TRUE),
      salience_ma7 = mean(salience_ma7, na.rm = TRUE),
      momentum_avg = mean(momentum, na.rm = TRUE),
      n_days = n(),
      .groups = "drop"
    )
}

# ============================================================================
# 5. MODÈLE 1: MULTIPLICATIF (LOG-LINEAR)
# ============================================================================

model_multiplicative <- function(poll_share, salience_share, momentum,
                                  beta1 = 1.0, beta2 = 0.5) {
  # vote_i = poll_i * exp(β1*salience + β2*momentum)
  # Puis normaliser pour sum-to-1

  alpha <- poll_share * exp(beta1 * salience_share + beta2 * momentum)
  vote_share <- alpha / sum(alpha)

  return(vote_share)
}

# ============================================================================
# 6. MODÈLE 2: BAYESIAN UPDATE (DIRICHLET)
# ============================================================================

model_bayesian_update <- function(poll_share, salience_share,
                                   n_poll = 500, n_pseudo = 100) {
  # alpha_i = n_poll * poll_i + n_pseudo * salience_i
  # vote_i = alpha_i / sum(alpha_i)

  alpha_prior <- n_poll * poll_share
  alpha_media <- n_pseudo * salience_share
  alpha_posterior <- alpha_prior + alpha_media

  vote_share <- alpha_posterior / sum(alpha_posterior)

  return(vote_share)
}

# ============================================================================
# 7. MODÈLE 3: DELTA CORRECTION
# ============================================================================

model_delta_correction <- function(poll_share, salience_now, salience_at_poll,
                                    beta = 0.5) {
  # vote_i = poll_i + β * (salience_now - salience_at_poll)
  # Puis normaliser

  delta_salience <- salience_now - salience_at_poll
  vote_raw <- poll_share + beta * delta_salience

  # Normaliser pour sum-to-1 et éviter valeurs négatives
  vote_raw <- pmax(vote_raw, 0)  # floor à 0
  vote_share <- vote_raw / sum(vote_raw)

  return(vote_share)
}

# ============================================================================
# 8. FONCTION DE VALIDATION TEMPORELLE
# ============================================================================

# Fonction pour prédire un poll cible à partir de polls précédents
predict_poll <- function(prior_poll_wave, target_poll_wave, polls_df, beta1 = 1.0, beta2 = 0.5, n_pseudo = 100) {

  # Poll prior (le plus récent avant le target)
  poll_prior <- polls_df %>%
    filter(poll_wave == prior_poll_wave) %>%
    select(candidat, vote_prior = vote_intention, date_prior = date_poll_mid, sample_size)

  # Poll target (actual)
  poll_target <- polls_df %>%
    filter(poll_wave == target_poll_wave) %>%
    select(candidat, vote_actual = vote_intention, date_target = date_poll_mid)

  if(nrow(poll_prior) == 0 || nrow(poll_target) == 0) {
    return(NULL)
  }

  # Média au moment du target
  date_target <- unique(poll_target$date_target)
  media_at_target <- get_media_at_date(date_target, window_days = 7)

  # Média au moment du prior (pour delta)
  date_prior <- unique(poll_prior$date_prior)
  media_at_prior <- get_media_at_date(date_prior, window_days = 7)

  # Combiner
  validation_data <- poll_prior %>%
    left_join(media_at_target, by = "candidat") %>%
    left_join(
      media_at_prior %>% select(candidat, salience_at_prior = salience_share_avg),
      by = "candidat"
    ) %>%
    left_join(poll_target, by = "candidat")

  # Remplacer NAs par 0 pour momentum
  validation_data <- validation_data %>%
    mutate(
      momentum_avg = replace_na(momentum_avg, 0),
      salience_at_prior = replace_na(salience_at_prior, mean(salience_share_avg, na.rm = TRUE))
    )

  # Prédictions des 3 modèles
  pred_m1 <- model_multiplicative(
    poll_share = validation_data$vote_prior,
    salience_share = validation_data$salience_share_avg,
    momentum = validation_data$momentum_avg,
    beta1 = beta1,
    beta2 = beta2
  )

  pred_m2 <- model_bayesian_update(
    poll_share = validation_data$vote_prior,
    salience_share = validation_data$salience_share_avg,
    n_poll = unique(poll_prior$sample_size),
    n_pseudo = n_pseudo
  )

  pred_m3 <- model_delta_correction(
    poll_share = validation_data$vote_prior,
    salience_now = validation_data$salience_share_avg,
    salience_at_poll = validation_data$salience_at_prior,
    beta = 0.5
  )

  results <- validation_data %>%
    mutate(
      pred_multiplicative = pred_m1,
      pred_bayesian = pred_m2,
      pred_delta = pred_m3,
      pred_baseline = vote_prior,
      prior_wave = prior_poll_wave,
      target_wave = target_poll_wave
    )

  return(results)
}

# ============================================================================
# 9. VALIDATION CROISÉE: POLLS 1→2, 1+2→3, 1+2+3→4
# ============================================================================

cat("\n=== TEMPORAL CROSS-VALIDATION ===\n\n")

# Identifier les polls disponibles
available_polls <- polls %>%
  filter(!is.na(poll_wave)) %>%
  distinct(poll_wave) %>%
  arrange(poll_wave) %>%
  pull(poll_wave)

cat("Available polls:", available_polls, "\n\n")

# Test 1: Poll 1 → Poll 2
cat("--- Test 1: Poll 1 → Poll 2 ---\n")
results_1to2 <- predict_poll(prior_poll_wave = 1, target_poll_wave = 2, polls_df = polls)

# Test 2: Poll 2 → Poll 3
cat("--- Test 2: Poll 2 → Poll 3 ---\n")
results_2to3 <- predict_poll(prior_poll_wave = 2, target_poll_wave = 3, polls_df = polls)

# Test 3: Poll 3 → Poll 4 (si existe)
results_3to4 <- NULL
if(4 %in% available_polls) {
  cat("--- Test 3: Poll 3 → Poll 4 ---\n")
  results_3to4 <- predict_poll(prior_poll_wave = 3, target_poll_wave = 4, polls_df = polls)
}

# Combiner tous les résultats
all_results <- bind_rows(
  results_1to2,
  results_2to3,
  results_3to4
)

cat("\n=== ALL VALIDATION RESULTS ===\n")
print(all_results %>%
        select(candidat, prior_wave, target_wave, vote_actual,
               pred_baseline, pred_multiplicative, pred_bayesian, pred_delta))

# ============================================================================
# 10. CALCUL MÉTRIQUES (MAPE) POUR TOUTES LES VALIDATIONS
# ============================================================================

calculate_mape <- function(actual, predicted) {
  mean(abs((actual - predicted) / actual)) * 100
}

# MAPE par test
mape_by_test <- all_results %>%
  group_by(prior_wave, target_wave) %>%
  summarise(
    mape_baseline = calculate_mape(vote_actual, pred_baseline),
    mape_multiplicative = calculate_mape(vote_actual, pred_multiplicative),
    mape_bayesian = calculate_mape(vote_actual, pred_bayesian),
    mape_delta = calculate_mape(vote_actual, pred_delta),
    .groups = "drop"
  )

cat("\n=== MAPE BY TEST ===\n")
print(mape_by_test)

# MAPE global (moyenne sur tous les tests)
mape_global <- all_results %>%
  summarise(
    mape_baseline = calculate_mape(vote_actual, pred_baseline),
    mape_multiplicative = calculate_mape(vote_actual, pred_multiplicative),
    mape_bayesian = calculate_mape(vote_actual, pred_bayesian),
    mape_delta = calculate_mape(vote_actual, pred_delta)
  )

cat("\n=== GLOBAL MAPE (ACROSS ALL TESTS) ===\n")
cat(sprintf("Baseline (Poll only):        %.2f%%\n", mape_global$mape_baseline))
cat(sprintf("Modèle 1 (Multiplicatif):    %.2f%% (Δ = %.2f%%)\n",
            mape_global$mape_multiplicative,
            mape_global$mape_baseline - mape_global$mape_multiplicative))
cat(sprintf("Modèle 2 (Bayesian Update):  %.2f%% (Δ = %.2f%%)\n",
            mape_global$mape_bayesian,
            mape_global$mape_baseline - mape_global$mape_bayesian))
cat(sprintf("Modèle 3 (Delta Correction): %.2f%% (Δ = %.2f%%)\n",
            mape_global$mape_delta,
            mape_global$mape_baseline - mape_global$mape_delta))

# ============================================================================
# 11. PRÉDICTION FINALE DE L'ÉLECTION (2 NOV 2025)
# ============================================================================

cat("\n\n=== FINAL ELECTION FORECAST (Nov 2, 2025) ===\n\n")

# Utiliser le dernier poll disponible comme prior
last_poll_wave <- max(available_polls)
last_poll <- polls %>%
  filter(poll_wave == last_poll_wave) %>%
  select(candidat, vote_prior = vote_intention, date_poll = date_poll_mid, sample_size)

cat("Using poll", last_poll_wave, "as prior (date:", as.character(unique(last_poll$date_poll)), ")\n")

# Média au jour de l'élection (ou le dernier disponible)
election_date <- as.Date("2025-11-02")
last_media_date <- max(media$date)

if(election_date > last_media_date) {
  cat("WARNING: Election date beyond media data. Using last available media date:", as.character(last_media_date), "\n")
  election_date <- last_media_date
}

media_at_election <- get_media_at_date(election_date, window_days = 7)
media_at_last_poll <- get_media_at_date(unique(last_poll$date_poll), window_days = 7)

# Combiner
forecast_data <- last_poll %>%
  left_join(media_at_election, by = "candidat") %>%
  left_join(
    media_at_last_poll %>% select(candidat, salience_at_last_poll = salience_share_avg),
    by = "candidat"
  ) %>%
  mutate(
    momentum_avg = replace_na(momentum_avg, 0),
    salience_at_last_poll = replace_na(salience_at_last_poll, mean(salience_share_avg, na.rm = TRUE))
  )

# Prédictions finales des 3 modèles
forecast_m1 <- model_multiplicative(
  poll_share = forecast_data$vote_prior,
  salience_share = forecast_data$salience_share_avg,
  momentum = forecast_data$momentum_avg,
  beta1 = 0.3,  # Réduit après validation (trop agressif à 1.0)
  beta2 = 0.2
)

forecast_m2 <- model_bayesian_update(
  poll_share = forecast_data$vote_prior,
  salience_share = forecast_data$salience_share_avg,
  n_poll = unique(last_poll$sample_size),
  n_pseudo = 50  # Réduit (média compte moins que poll)
)

forecast_m3 <- model_delta_correction(
  poll_share = forecast_data$vote_prior,
  salience_now = forecast_data$salience_share_avg,
  salience_at_poll = forecast_data$salience_at_last_poll,
  beta = 0.3  # Réduit
)

forecast_final <- forecast_data %>%
  mutate(
    forecast_baseline = vote_prior,
    forecast_multiplicative = forecast_m1,
    forecast_bayesian = forecast_m2,
    forecast_delta = forecast_m3
  ) %>%
  select(candidat, vote_prior, starts_with("forecast_"))

cat("\n=== FINAL FORECAST ===\n")
print(forecast_final, n = Inf)

# Sauvegarder forecast final
write_csv(forecast_final, "output/final_forecast_2025-11-02.csv")
cat("\nFinal forecast saved to output/final_forecast_2025-11-02.csv\n")

# ============================================================================
# 12. VISUALISATION
# ============================================================================

# Graphique 1: Validation croisée
results_long <- all_results %>%
  select(candidat, prior_wave, target_wave, vote_actual, starts_with("pred_")) %>%
  pivot_longer(
    cols = starts_with("pred_"),
    names_to = "model",
    values_to = "prediction",
    names_prefix = "pred_"
  ) %>%
  mutate(
    model = factor(model,
                   levels = c("baseline", "multiplicative", "bayesian", "delta"),
                   labels = c("Baseline", "Multiplicatif", "Bayesian", "Delta")),
    test_label = paste0("Poll ", prior_wave, " → ", target_wave)
  )

p1 <- ggplot(results_long, aes(x = vote_actual, y = prediction,
                                color = model, shape = model)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", alpha = 0.5) +
  geom_point(size = 3, alpha = 0.7) +
  facet_wrap(~test_label, scales = "free") +
  scale_color_brewer(palette = "Set1") +
  labs(
    title = "Validation Croisée Temporelle: Actual vs Predicted",
    x = "Vote Intention Actual",
    y = "Predicted Vote Share",
    color = "Model",
    shape = "Model"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

# Graphique 2: MAPE par test
mape_long <- mape_by_test %>%
  pivot_longer(
    cols = starts_with("mape_"),
    names_to = "model",
    values_to = "mape",
    names_prefix = "mape_"
  ) %>%
  mutate(
    model = factor(model,
                   levels = c("baseline", "multiplicative", "bayesian", "delta"),
                   labels = c("Baseline", "Multiplicatif", "Bayesian", "Delta")),
    test_label = paste0("Poll ", prior_wave, " → ", target_wave)
  )

p2 <- ggplot(mape_long, aes(x = model, y = mape, fill = model)) +
  geom_col() +
  geom_text(aes(label = sprintf("%.1f%%", mape)), vjust = -0.5, size = 3) +
  facet_wrap(~test_label) +
  scale_fill_brewer(palette = "Set1") +
  labs(
    title = "MAPE par Test et Modèle",
    subtitle = "Lower is better",
    x = NULL,
    y = "Mean Absolute Percentage Error (%)"
  ) +
  theme_minimal() +
  theme(legend.position = "none", axis.text.x = element_text(angle = 45, hjust = 1))

# Graphique 3: Forecast final
forecast_long <- forecast_final %>%
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

p3 <- ggplot(forecast_long, aes(x = candidat, y = forecast, fill = model)) +
  geom_col(position = "dodge") +
  scale_fill_brewer(palette = "Set1") +
  labs(
    title = "Forecast Final Élection Montréal (2 nov 2025)",
    subtitle = paste0("Based on poll ", last_poll_wave, " + media data through ", as.character(election_date)),
    x = "Candidat",
    y = "Forecasted Vote Share",
    fill = "Model"
  ) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

print(p1)
print(p2)
print(p3)

# Sauvegarder figures
ggsave("output/figures/validation_cross_temporal.png", p1, width = 12, height = 8, dpi = 300)
ggsave("output/figures/mape_by_test.png", p2, width = 10, height = 6, dpi = 300)
ggsave("output/figures/final_forecast.png", p3, width = 10, height = 6, dpi = 300)

cat("\n=== DONE ===\n")
cat("Figures saved to output/figures/\n")
