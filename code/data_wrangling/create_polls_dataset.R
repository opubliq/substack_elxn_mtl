# ==============================================================================
# CREATE POLLS DATASET - Montreal Municipal Election 2025
# ==============================================================================
#
# This script creates a long-format dataset of polling data for the
# Montreal 2025 mayoral election.
#
# Structure: One row per candidate-poll combination
# Output: data/processed/polls_dataset.rds
#
# ==============================================================================

# Load libraries ---------------------------------------------------------------
library(tidyverse)
library(lubridate)

candidates <- c(
  "soraya_martinez_ferrada",
  "luc_rabouin",
  "craig_sauve",
  "gilbert_thibodeau",
  "jf_kacou",
  "indecis"
)

# ==============================================================================
# POLL 1 - ENTRER LES DONNEES
# ==============================================================================

poll_1 <- tibble(
  poll_id = "poll_1",

  # METADONNEES DU SONDAGE
  poll_firm = "leger",
  sample_size = 500,
  methodology = "",
  date_debut = ymd("2025-09-15"),
  date_fin = ymd("2025-09-21"),
  marge_erreur = 1 / sqrt(500),

  # CANDIDATS ET INTENTIONS DE VOTE
  candidat = candidates,

  vote_intention = c(
    0.2,
    0.11,
    0.06,
    0.05,
    0.02,
    0.48
  )
)


# ==============================================================================
# POLL 2 - ENTRER LES DONNEES
# ==============================================================================

poll_2 <- tibble(
  poll_id = "poll_2",

  # METADONNEES DU SONDAGE
  poll_firm = "leger",
  sample_size = 500,
  methodology = "",
  date_debut = ymd("2025-09-26"),
  date_fin = ymd("2025-09-30"),
  marge_erreur = 1 / sqrt(500),

  # CANDIDATS ET INTENTIONS DE VOTE
  candidat = candidates,

  vote_intention = c(
    0.21,
    0.12,
    0.08,
    0.07,
    0.02,
    0.42
  )
)


# ==============================================================================
# POLL 3 - ENTRER LES DONNEES
# ==============================================================================

poll_3 <- tibble(
  poll_id = "poll_3",

  # METADONNEES DU SONDAGE
  poll_firm = "segma",
  sample_size = 1002,
  methodology = "",
  date_debut = ymd("2025-10-03"),
  date_fin = ymd("2025-10-09"),
  marge_erreur = 1 / sqrt(1002),

  # CANDIDATS ET INTENTIONS DE VOTE
  candidat = candidates,

  vote_intention = c(
    0.26,
    0.18,
    0.05,
    0.08,
    0.03,
    0.37
  )
)


# ==============================================================================
# POLL 4 - ENTRER LES DONNEES
# ==============================================================================

poll_4 <- tibble(
  poll_id = "poll_4",

  # METADONNEES DU SONDAGE
  poll_firm = "pallas",
  sample_size = 608,
  methodology = "",
  date_debut = ymd("2025-10-25"),
  date_fin = ymd("2025-10-25"),
  marge_erreur = 1 / sqrt(608),

  # CANDIDATS ET INTENTIONS DE VOTE
  candidat = candidates,

  vote_intention = c(
    0.33,
    0.18,
    0.06,
    0.11,
    0.03,
    0.29
  )
)


# ==============================================================================
# COMBINER ET SAUVEGARDER
# ==============================================================================

# Combiner tous les sondages
polls_dataset <- bind_rows(
  poll_1,
  poll_2,
  poll_3,
  poll_4
) %>%
  # Reorganiser les colonnes
  select(
    poll_id,
    candidat,
    vote_intention,
    date_debut,
    date_fin,
    marge_erreur,
    poll_firm,
    sample_size,
    methodology
  ) %>%
  # Ordonner par date et candidat
  arrange(date_debut, candidat)

# Afficher un apercu
print(polls_dataset)

# Verifications de base
cat("\n=== VERIFICATIONS ===\n")
cat("Nombre total de rangees:", nrow(polls_dataset), "\n")
cat("Nombre de sondages:", n_distinct(polls_dataset$poll_id), "\n")
cat("Candidats uniques:", paste(unique(polls_dataset$candidat), collapse = ", "), "\n")

# Verifier si les intentions de vote somment a 100% par sondage
somme_par_poll <- polls_dataset %>%
  group_by(poll_id) %>%
  summarise(
    total = sum(vote_intention, na.rm = TRUE),
    nb_na = sum(is.na(vote_intention))
  )
print(somme_par_poll)

# Sauvegarder le dataset
output_path <- "data/processed/polls.rds"
saveRDS(polls_dataset, output_path)

cat("\nDataset sauvegarde:", output_path, "\n")