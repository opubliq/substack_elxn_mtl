# ============================================================================
# MODEL FUNCTIONS
# ============================================================================
# Définit les 3 approches de combinaison polls + média

#' Modèle Multiplicatif (Log-Linear)
#'
#' vote_i = poll_i * exp(β1*salience + β2*momentum)
#' Puis normalisation pour sum-to-1
#'
#' @param poll_share Vecteur de proportions du poll (incluant indécis)
#' @param salience_share Vecteur de saillance relative média
#' @param momentum Vecteur de momentum (delta salience)
#' @param beta1 Poids sur salience
#' @param beta2 Poids sur momentum
#' @return Vecteur de vote shares prédits (sum=1)
model_multiplicative <- function(poll_share, salience_share, momentum,
                                  beta1 = 0.3, beta2 = 0.2) {
  alpha <- poll_share * exp(beta1 * salience_share + beta2 * momentum)
  vote_share <- alpha / sum(alpha)
  return(vote_share)
}


#' Modèle Bayesian Update (Dirichlet)
#'
#' alpha_i = n_poll * poll_i + n_pseudo * salience_i
#' vote_i = alpha_i / sum(alpha_i)
#'
#' @param poll_share Vecteur de proportions du poll (incluant indécis)
#' @param salience_share Vecteur de saillance relative média
#' @param n_poll Sample size effectif du poll
#' @param n_pseudo Pseudo sample size des médias
#' @return Vecteur de vote shares prédits (sum=1)
model_bayesian_update <- function(poll_share, salience_share,
                                   n_poll = 500, n_pseudo = 50) {
  alpha_prior <- n_poll * poll_share
  alpha_media <- n_pseudo * salience_share
  alpha_posterior <- alpha_prior + alpha_media

  vote_share <- alpha_posterior / sum(alpha_posterior)
  return(vote_share)
}


#' Modèle Delta Correction
#'
#' vote_i = poll_i + β * (salience_now - salience_at_poll)
#' Puis normalisation et floor à 0
#'
#' @param poll_share Vecteur de proportions du poll (incluant indécis)
#' @param salience_now Saillance au moment de la prédiction
#' @param salience_at_poll Saillance au moment du poll
#' @param beta Poids sur le delta
#' @return Vecteur de vote shares prédits (sum=1)
model_delta_correction <- function(poll_share, salience_now, salience_at_poll,
                                    beta = 0.3) {
  delta_salience <- salience_now - salience_at_poll
  vote_raw <- poll_share + beta * delta_salience

  # Floor à 0 et normaliser
  vote_raw <- pmax(vote_raw, 0)
  vote_share <- vote_raw / sum(vote_raw)

  return(vote_share)
}


#' Wrapper: Prédire avec un modèle donné
#'
#' @param model_type Type de modèle: "multiplicative", "bayesian", "delta"
#' @param poll_data Data frame avec colonnes: candidat, vote_share
#' @param media_data Data frame avec colonnes: candidat, salience_share, momentum
#' @param media_at_poll_data Pour delta: salience au moment du poll
#' @param params Liste de hyperparamètres
#' @return Data frame avec candidat + prediction
predict_with_model <- function(model_type, poll_data, media_data,
                                media_at_poll_data = NULL,
                                params = list()) {

  # Merge poll + media
  combined <- poll_data %>%
    left_join(media_data, by = "candidat")

  if (model_type == "multiplicative") {
    beta1 <- params$beta1 %||% 0.3
    beta2 <- params$beta2 %||% 0.2

    pred <- model_multiplicative(
      poll_share = combined$vote_share,
      salience_share = combined$salience_share,
      momentum = combined$momentum,
      beta1 = beta1,
      beta2 = beta2
    )

  } else if (model_type == "bayesian") {
    n_poll <- params$n_poll %||% 500
    n_pseudo <- params$n_pseudo %||% 50

    pred <- model_bayesian_update(
      poll_share = combined$vote_share,
      salience_share = combined$salience_share,
      n_poll = n_poll,
      n_pseudo = n_pseudo
    )

  } else if (model_type == "delta") {
    beta <- params$beta %||% 0.3

    if (is.null(media_at_poll_data)) {
      stop("delta model requires media_at_poll_data")
    }

    combined <- combined %>%
      left_join(media_at_poll_data %>% select(candidat, salience_at_poll = salience_share),
                by = "candidat")

    pred <- model_delta_correction(
      poll_share = combined$vote_share,
      salience_now = combined$salience_share,
      salience_at_poll = combined$salience_at_poll,
      beta = beta
    )

  } else {
    stop("Unknown model_type: ", model_type)
  }

  result <- tibble(
    candidat = combined$candidat,
    prediction = pred
  )

  return(result)
}
