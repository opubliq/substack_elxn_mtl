# ============================================================================
# 02: ENTRAÎNEMENT ET VALIDATION DES MODÈLES
# ============================================================================
# Valide les 3 modèles hybrides sur horizons temporels multiples
# Output: data/outputs/validation_results.rds

library(tidyverse)
source("R/functions/model_functions.R")
source("R/functions/data_prep.R")
source("R/functions/validation.R")

cat("=== 02: MODEL TRAINING & VALIDATION ===\n\n")

# ----------------------------------------------------------------------------
# 1. Charger données préparées
# ----------------------------------------------------------------------------

cat("Loading prepared data...\n")
model_data <- readRDS("data/processed/model_data.rds")

polls <- model_data$polls
media_features <- model_data$media_features

cat("  Polls loaded:", n_distinct(polls$poll_wave), "waves\n")
cat("  Media features loaded:", nrow(media_features), "rows\n")

# ----------------------------------------------------------------------------
# 2. Définir hyperparamètres des modèles
# ----------------------------------------------------------------------------

cat("\nDefining model hyperparameters...\n")

# Hyperparamètres optimisés (réduits après expériences initiales)
hyperparams <- list(
  multiplicative = list(
    beta1 = 0.3,  # Poids sur salience (réduit de 1.0)
    beta2 = 0.2   # Poids sur momentum (réduit de 0.5)
  ),
  bayesian = list(
    n_poll = 500,  # Sample size poll (fixe)
    n_pseudo = 50  # Pseudo sample size média (réduit de 100)
  ),
  delta = list(
    beta = 0.3  # Poids sur delta salience (réduit de 0.5)
  )
)

cat("  Hyperparams:\n")
cat("    Multiplicative: beta1=", hyperparams$multiplicative$beta1,
    ", beta2=", hyperparams$multiplicative$beta2, "\n")
cat("    Bayesian: n_pseudo=", hyperparams$bayesian$n_pseudo, "\n")
cat("    Delta: beta=", hyperparams$delta$beta, "\n")

# ----------------------------------------------------------------------------
# 3. Validation croisée temporelle
# ----------------------------------------------------------------------------

cat("\nRunning temporal cross-validation...\n")

# Définir paires (prior, target) pour validation
available_waves <- polls %>%
  filter(!is.na(poll_wave)) %>%
  distinct(poll_wave) %>%
  pull(poll_wave) %>%
  sort()

# Créer paires: 1→2, 2→3, 3→4 (si disponible)
test_pairs <- list()
for (i in seq_along(available_waves)[-length(available_waves)]) {
  test_pairs[[length(test_pairs) + 1]] <- c(available_waves[i], available_waves[i+1])
}

cat("  Test pairs:", paste(sapply(test_pairs, function(x) paste(x, collapse="→")), collapse=", "), "\n")

# Valider
validation_results <- validate_multiple_horizons(
  polls = polls,
  media_features = media_features,
  test_pairs = test_pairs,
  models = c("baseline", "multiplicative", "bayesian", "delta"),
  params = hyperparams
)

cat("  Validation complete:", nrow(validation_results), "predictions\n")

# ----------------------------------------------------------------------------
# 4. Calculer métriques
# ----------------------------------------------------------------------------

cat("\nComputing validation metrics...\n")
metrics <- compute_validation_metrics(validation_results)

cat("\n--- MAPE by test ---\n")
print(metrics$by_test %>% arrange(prior_wave, target_wave, model))

cat("\n--- MAPE global ---\n")
print(metrics$global %>% arrange(mape_global))

# Identifier meilleur modèle
best_model <- metrics$global %>%
  slice_min(mape_global, n = 1) %>%
  pull(model)

cat("\n  Best model (lowest global MAPE):", best_model, "\n")

# ----------------------------------------------------------------------------
# 5. Sauvegarder résultats
# ----------------------------------------------------------------------------

cat("\nSaving validation results...\n")

# Créer répertoire outputs si nécessaire
dir.create("data/outputs", showWarnings = FALSE, recursive = TRUE)

output <- list(
  validation_results = validation_results,
  metrics = metrics,
  hyperparams = hyperparams,
  best_model = best_model,
  metadata = list(
    date_trained = Sys.time(),
    n_tests = length(test_pairs),
    test_pairs = test_pairs
  )
)

saveRDS(output, "data/outputs/validation_results.rds")

cat("  Saved to: data/outputs/validation_results.rds\n")

cat("\n=== MODEL TRAINING & VALIDATION COMPLETE ===\n")
