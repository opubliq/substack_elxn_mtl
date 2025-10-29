################################################################################
# Détection des candidats à la mairie de Montréal 2025 dans les médias
#
# Ce script charge les titres depuis le 10 septembre 2024 et détecte
# la présence des candidats à la mairie de Montréal dans les textes.
#
# Auteur: Adrien
# Date: 2025-10-29
################################################################################

# Charger les librairies nécessaires
library(dplyr)
library(tidyr)
library(tube)
library(lubridate)
library(stringr)

# Configuration
ENVIRONNEMENT <- "DEV"  # ou "PROD"
DATE_DEBUT <- as.Date("2025-10-25")  # Change à "2024-09-10" pour charger depuis septembre

# Liste des candidats à la mairie de Montréal 2025
candidats <- list(
  "soraya_martinez_ferrada" = c("Soraya Martinez Ferrada", "Soraya Martinez-Ferrada",
                                  "Martinez Ferrada", "Soraya Ferrada"),
  "luc_rabouin" = c("Luc Rabouin"),
  "craig_sauve" = c("Craig Sauvé", "Craig Sauve"),
  "gilbert_thibodeau" = c("Gilbert Thibodeau"),
  "jean_francois_kacou" = c("Jean-François Kacou", "Jean-Francois Kacou", "JF Kacou")
)

####################################################################
####### CONNEXION ET CHARGEMENT DES DONNÉES ########################
####################################################################

cat("\n=== Connexion au datamart ===\n")
condm <- tube::ellipse_connect(ENVIRONNEMENT, "datamarts")

cat("\n=== Chargement des données depuis le 10 septembre 2024 ===\n")

# Créer le filtre de date pour SQL (comme dans le refiner hot-20)
# Format: "2024-09-10 00:00:00"
date_filter_str <- paste0(as.character(DATE_DEBUT), " 00:00:00")

cat(sprintf("Filtre de date: >= %s\n", date_filter_str))

# Construire le filtre SQL avec parse_datetime (comme dans radar-hot-20.R)
date_filter <- sprintf(
  "parse_datetime(CASE
    WHEN LENGTH(headline_stop_montreal_tz) = 23 THEN headline_stop_montreal_tz
    WHEN LENGTH(headline_stop_montreal_tz) = 19 THEN headline_stop_montreal_tz || '.000'
    ELSE NULL END, 'yyyy-MM-dd HH:mm:ss.SSS') >= parse_datetime('%s', 'yyyy-MM-dd HH:mm:ss')",
  date_filter_str
)

# Charger les objets saillants avec filtre SQL direct
df_headlines <- tube::ellipse_query(condm, "vitrine_datamart-salient_headlines_objects") |>
  filter(dbplyr::sql(date_filter)) |>
  arrange(desc(headline_stop_montreal_tz)) |>
  collect()

tube::ellipse_disconnect(condm)

# Ajouter la colonne date pour faciliter les analyses
df_headlines <- df_headlines |>
  mutate(date_montreal = as.Date(headline_stop_montreal_tz))

cat(sprintf("Données chargées: %d titres depuis le %s\n",
            nrow(df_headlines), DATE_DEBUT))

if (nrow(df_headlines) == 0) {
  stop("Aucune donnée disponible pour la période demandée!")
}

####################################################################
####### FONCTION DE DÉTECTION DES CANDIDATS ########################
####################################################################

# Fonction vectorisée pour détecter si un texte contient un des noms du candidat
detecter_candidat <- function(texte, noms_candidat) {
  # Remplacer les NA par des chaînes vides (tidyr::replace_na est le plus robuste)
  texte_clean <- tidyr::replace_na(texte, "")

  # Créer un pattern regex qui cherche n'importe lequel des noms
  # On utilise word boundaries pour éviter les faux positifs
  pattern <- paste0("\\b(", paste(noms_candidat, collapse = "|"), ")\\b")

  # Détecter et convertir en 1/0
  as.integer(str_detect(texte_clean, regex(pattern, ignore_case = TRUE)))
}

####################################################################
####### DÉTECTION DES CANDIDATS DANS LES TEXTES ####################
####################################################################

cat("\n=== Détection des candidats dans les textes ===\n")

# Créer le texte combiné (title + body) pour la recherche
df_filtered <- df_headlines |>
  mutate(
    texte_complet = paste(title, body, sep = " ")
  )

# Détecter chaque candidat
for (candidat_id in names(candidats)) {
  noms <- candidats[[candidat_id]]
  cat(sprintf("Détection de %s (%s)...\n",
              candidat_id, paste(noms, collapse = ", ")))

  df_filtered <- df_filtered |>
    mutate(!!candidat_id := detecter_candidat(texte_complet, noms))
}

# Filtrer pour ne garder que les textes qui mentionnent au moins un candidat
df_final <- df_filtered |>
  filter(
    soraya_martinez_ferrada == 1 |
    luc_rabouin == 1 |
    craig_sauve == 1 |
    gilbert_thibodeau == 1 |
    jean_francois_kacou == 1
  ) |>
  select(
    date = date_montreal,
    media_id,
    title,
    body,
    url,
    texte_complet,
    soraya_martinez_ferrada,
    luc_rabouin,
    craig_sauve,
    gilbert_thibodeau,
    jean_francois_kacou,
    headline_minutes,
    headline_start_montreal_tz,
    headline_stop_montreal_tz
  ) |>
  arrange(desc(date))

####################################################################
####### STATISTIQUES ET AFFICHAGE ##################################
####################################################################

cat("\n=== RÉSULTATS ===\n\n")
cat(sprintf("Total de textes mentionnant au moins un candidat: %d\n", nrow(df_final)))
cat(sprintf("Période couverte: du %s au %s\n",
            min(df_final$date), max(df_final$date)))

cat("\n=== Nombre de mentions par candidat ===\n")
cat(sprintf("Soraya Martinez Ferrada: %d mentions\n", sum(df_final$soraya_martinez_ferrada)))
cat(sprintf("Luc Rabouin: %d mentions\n", sum(df_final$luc_rabouin)))
cat(sprintf("Craig Sauvé: %d mentions\n", sum(df_final$craig_sauve)))
cat(sprintf("Gilbert Thibodeau: %d mentions\n", sum(df_final$gilbert_thibodeau)))
cat(sprintf("Jean-François Kacou: %d mentions\n", sum(df_final$jean_francois_kacou)))

cat("\n=== Distribution par média ===\n")
df_media <- df_final |>
  group_by(media_id) |>
  summarise(
    n_textes = n(),
    .groups = "drop"
  ) |>
  arrange(desc(n_textes))

print(df_media)

cat("\n=== Distribution par date (derniers 30 jours) ===\n")
df_dates <- df_final |>
  filter(date >= Sys.Date() - 30) |>
  group_by(date) |>
  summarise(
    n_textes = n(),
    soraya = sum(soraya_martinez_ferrada),
    luc = sum(luc_rabouin),
    craig = sum(craig_sauve),
    gilbert = sum(gilbert_thibodeau),
    jf = sum(jean_francois_kacou),
    .groups = "drop"
  ) |>
  arrange(desc(date))

print(df_dates, n = 30)

cat("\n=== Aperçu des premiers résultats ===\n")
df_apercu <- df_final |>
  head(10) |>
  select(date, media_id, title, soraya_martinez_ferrada:jean_francois_kacou)

print(df_apercu, n = 10)

####################################################################
####### SAUVEGARDE (OPTIONNEL) #####################################
####################################################################

# Décommenter pour sauvegarder
# saveRDS(df_final, "data/election_mtl_2025_candidats.rds")
# write.csv(df_final, "data/election_mtl_2025_candidats.csv", row.names = FALSE)

cat("\n✅ Script terminé!\n")
cat(sprintf("\nLe dataframe 'df_final' contient %d textes avec détection des candidats.\n", nrow(df_final)))
cat("Colonnes: date, media_id, title, body, url, texte_complet, + colonnes binaires par candidat\n\n")
