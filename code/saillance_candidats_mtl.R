################### Section 1 ############################
############## Extraire les données #####################

# Charger les librairies nécessaires
library(tidyverse)
library(lubridate)
library(tube)
library(jsonlite)
library(devtools)
library(ellipsellm)
library(glue)
library(httr2)
library(purrr)
library(tictoc)
library(beepr)
library(stringr)

set.seed(42)

# Lancer le chrono
tic("Temps d'exécution total")

# Charger les données locales depuis AWS
con <- ellipse_connect("PROD")

# Définir les bornes temporelles pour l'analyse
# Période électorale: 10 septembre au 2 novembre 2025
borne_inf <- ymd_hms("2025-09-10 00:00:00", tz = "America/Toronto")
borne_sup <- ymd_hms("2025-11-03 23:59:59", tz = "America/Toronto")

# On va s'intéresser aux Unes médiatiques 🗞️
df_local <- ellipse_query(con, "r-media-headlines") |>
  filter(extraction_year == 2025,
         extraction_month %in% 09:11)|>
  collect() # Rappel : collect() rapporte les données de AWS vers notre machine

ellipse_disconnect(con)

# Les timestamps AWS sont en UTC, nous allons devoir les convertir
to_localtime <- function(dt, tz = "America/Toronto") {
  with_tz(dt, tzone = tz)
}

# Attention: haute voltige! 🤸 commentaires à partir de la colonne 80 🚀         # nolint start
df_headline_duration <-
  df_local |>                                                                   # C'est un départ 🏎️
  mutate(extraction_localtime =                                                 # On veut une colonne datetime qui soit dans notre fuseau horaire local...
           to_localtime(ymd_hms(paste0(as.character(extraction_date),           # (on utilise notre fonction `to_localtime`)
                                       extraction_time)))) |>
  filter(extraction_localtime >= borne_inf,                                     # ... pour isoler la période qui nous intéresse
         extraction_localtime <= borne_sup) |>
  select(media_id, extraction_localtime, url = metadata_url) |>                 # On réduit aux colonnes nécessaires à nos calculs.
  arrange(extraction_localtime) |>                                              # On place tout ça en ordre chronologique...
  mutate(headline_order = 1 + cumsum(url != lag(url, default = first(url))),    # ... attribue un rang à chaque nouvelle dans la journée...
         .by = media_id) |>                                                     # ... et ce, par média.
  mutate(headline_start = min(extraction_localtime),                            # On attribue une date et heure de début,
         headline_stop  = max(extraction_localtime),                            # de fin,
         headline_minutes = round(as.numeric(difftime(headline_stop,            # ainsi qu'une durée calculée pour chaque "Une"...
                                                      headline_start,
                                                      units = "mins")),
                                  0),
         .by = c(media_id, headline_order, url)) |>                             # ... par média/rang/url.
  distinct(media_id, headline_order,                                            # On ne conserve que l'essentiel...
           headline_start, headline_stop, headline_minutes, url) |>
  mutate(headline_prop = round(headline_minutes / sum(pick(headline_minutes)),  # ... pour calculer la proportion de temps qu'une "Une" occupe dans la période...
                               2),
         .by = media_id) |>                                                     # ... pour chacun des médias.
  inner_join(df_local, by = join_by(url == metadata_url), multiple = "any") |>  # Puis on joint avec nous-même...
  select(media_id = media_id.x, starts_with("headline"), title, url, body, author) |>   # ... pour récupérer les colones que nous avions mises de côté.
  arrange(media_id, headline_order) %>%                                         # Et enfin, on ordonne par média et par ordre chronologique de "Une"!
  filter(headline_minutes > 10)                                                  # Et faut au moins que la nouvelle ait été scrappé 3x, sinon pas assez important

# Enfin, on peut nettoyer les titres et les textes
to_remove <- "\\||CTV News|JDM|La Presse|Le Devoir|Radio-Canada|Radio-Canada Info|TVA Nouvelles|RCI|CBC|Global News|GAM|GN|NP|TTS|VS|FXN|CNN|The Star|Montreal Gazette|National Post|The Globe and Mail|Fox News fox news"

# Nettoyage des titres et des textes - Focus sur médias montréalais/québécois
df_clean <- df_headline_duration |>
  mutate(
    title = stringr::str_remove_all(title, to_remove) |> stringr::str_squish(),
    body = stringr::str_remove_all(body, to_remove) |> stringr::str_squish(),  # Nettoyage des textes
    langue = case_when(
      media_id %in% c("JDM", "LED", "TVA", "LAP", "RCI", "MG") ~ "fr",
      media_id %in% c("CBC", "CTV", "VS", "GN", "NP", "GAM", "TTS", "FXN", "CNN") ~ "en",
      TRUE ~ "autre"  # Sécurité
    ),
    region = case_when(
      media_id %in% c("JDM", "LAP", "LED", "TVA", "RCI") ~ "MTL_QC",  # Médias montréalais/québécois
      media_id %in% c("MG", "CBC", "CTV") ~ "MTL_EN",  # Médias anglophones montréalais
      TRUE ~ "Autre"
    )
  ) |>
  filter(region %in% c("MTL_QC", "MTL_EN"))  # Focus sur médias montréalais

################### Section 2 ############################
############## Filtrer articles sur l'élection municipale + Extraire candidats ET enjeux #############

model_to_use <- "gpt-4o-mini"  # Changer ici le modèle (https://platform.openai.com/docs/models)

# Étape 1: Filtrer pour garder seulement les articles sur l'élection municipale
print("Étape 1: Identification des articles sur l'élection municipale...")

df_election <- df_clean %>%
  rowwise() %>%
  mutate(
    prompt_election = glue("
      Voici un article de presse:
      **Titre :** {title}
      **Extrait :** ```{body}```

      Détermine si cet article parle de l'élection municipale de Montréal de 2025.

      Réponds uniquement par 'OUI' si l'article mentionne:
      - L'élection municipale de Montréal 2025
      - Les candidats à la mairie (Martinez Ferrada, Rabouin, Sauvé, Thibodeau, Kacou)
      - Des enjeux dans le contexte de la campagne électorale municipale

      Réponds 'NON' si l'article ne parle pas d'élection ou parle d'autres sujets.

      Réponse (OUI ou NON):
    "),

    conversation_election = list(openai_create_conversation(
      user_message = prompt_election,
      system_message = "Tu es un classificateur expert. Tu dois déterminer si un article parle de l'élection municipale de Montréal 2025."
    )),

    response_election = list(openai_chat_completion(messages = conversation_election, model = model_to_use)),
    est_election = str_to_upper(trimws(response_election$content))
  ) %>%
  ungroup() %>%
  filter(est_election == "OUI")

print(glue("Nombre d'articles sur l'élection municipale: {nrow(df_election)}"))

# Étape 2: Extraire les candidats ET les enjeux dans ces articles
print("Étape 2: Extraction des candidats et enjeux...")

df_extraits <- df_election %>%
  rowwise() %>%
  mutate(
    # PROMPT 1: Extraction des candidats
    prompt_candidats = glue("
      Voici un article sur l'élection municipale de Montréal:
      **Titre :** {title}
      **Extrait :** ```{body}```

      Identifie les candidats suivants mentionnés:
      - Martinez Ferrada (ou Soraya Martinez Ferrada, ou Soraya)
      - Rabouin (ou Craig Rabouin, ou Craig)
      - Sauvé (ou Catherine Sauvé, ou Catherine)
      - Thibodeau (ou Renée Thibodeau, ou Renée)
      - Kacou (ou Yannick Kacou, ou Yannick)

      Retourne les noms de famille séparés par des virgules.
      Si aucun: 'aucun'.

      Exemple: 'Martinez Ferrada, Rabouin'
    "),

    conversation_candidats = list(openai_create_conversation(
      user_message = prompt_candidats,
      system_message = "Tu es un expert en extraction de candidats municipaux."
    )),

    response_candidats = list(openai_chat_completion(messages = conversation_candidats, model = model_to_use)),
    candidats_mentionnes = response_candidats$content,

    # PROMPT 2: Extraction des enjeux
    prompt_enjeux = glue("
      Voici un article sur l'élection municipale de Montréal:
      **Titre :** {title}
      **Extrait :** ```{body}```

      Identifie les enjeux suivants mentionnés (utilise EXACTEMENT ces catégories):

      1. 'Coût des loyers / Accès à la propriété'
      2. 'Itinérance / Logement social'
      3. 'Congestion routière / Chantiers'
      4. 'Transport collectif'
      5. 'Sécurité / Criminalité'
      6. 'Taxes'
      7. 'Propreté / Déneigement / Services publics'
      8. 'Infrastructures de transport'
      9. 'Développement économique'
      10. 'Bureaucratie / Réglementation'
      11. 'Réduction des dépenses'
      12. 'Changements climatiques'
      13. 'Langue française'
      14. 'Transport actif'
      15. 'Culture / Loisirs'

      Retourne les enjeux séparés par des virgules.
      Si aucun: 'aucun'.
      NE CRÉE PAS de nouvelles catégories.
    "),

    conversation_enjeux = list(openai_create_conversation(
      user_message = prompt_enjeux,
      system_message = "Tu es un expert en classification d'enjeux électoraux municipaux. Utilise strictement les catégories fournies."
    )),

    response_enjeux = list(openai_chat_completion(messages = conversation_enjeux, model = model_to_use)),
    enjeux_mentionnes = response_enjeux$content
  ) %>%
  ungroup()

# Sauvegarder les données brutes avec extraction
saveRDS(df_extraits, "/Users/adrien/Library/CloudStorage/Dropbox/travail/opubliq/substack_elxn_mtl/data/processed/candidats_enjeux_extraction.rds")

toc()

################### Section 3 ############################
############## Calculer saillance des CANDIDATS #############

print("Étape 3: Calcul de la saillance des candidats...")

df_candidats_long <- df_extraits %>%
  mutate(date = as.Date(headline_start)) %>%
  filter(candidats_mentionnes != "aucun") %>%
  separate_rows(candidats_mentionnes, sep = ",") %>%
  mutate(
    candidats_mentionnes = tolower(trimws(candidats_mentionnes)),
    candidats_mentionnes = str_remove_all(candidats_mentionnes, "[[:punct:]]")
  ) %>%
  group_by(region, date, candidats_mentionnes) %>%
  summarise(
    n = n(),
    total_minutes = sum(headline_minutes, na.rm = TRUE),
    urls = list(unique(url)),
    titres = list(unique(title)),
    .groups = "drop"
  ) %>%
  mutate(indice_absolu = n * total_minutes) %>%
  group_by(region, date) %>%
  mutate(
    total_absolu = sum(indice_absolu),
    indice_relatif = indice_absolu / total_absolu
  ) %>%
  ungroup() %>%
  filter(!is.na(candidats_mentionnes) & candidats_mentionnes != "")

# Sauvegarder
saveRDS(df_candidats_long, "/Users/adrien/Library/CloudStorage/Dropbox/travail/opubliq/substack_elxn_mtl/data/processed/saillance_candidats.rds")

################### Section 3b ############################
############## Calculer saillance des ENJEUX #############

print("Étape 4: Calcul de la saillance des enjeux...")

df_enjeux_long <- df_extraits %>%
  mutate(date = as.Date(headline_start)) %>%
  filter(enjeux_mentionnes != "aucun") %>%
  separate_rows(enjeux_mentionnes, sep = ",") %>%
  mutate(
    enjeux_mentionnes = trimws(enjeux_mentionnes)
  ) %>%
  group_by(region, date, enjeux_mentionnes) %>%
  summarise(
    n = n(),
    total_minutes = sum(headline_minutes, na.rm = TRUE),
    urls = list(unique(url)),
    titres = list(unique(title)),
    .groups = "drop"
  ) %>%
  mutate(indice_absolu = n * total_minutes) %>%
  group_by(region, date) %>%
  mutate(
    total_absolu = sum(indice_absolu),
    indice_relatif = indice_absolu / total_absolu
  ) %>%
  ungroup() %>%
  filter(!is.na(enjeux_mentionnes) & enjeux_mentionnes != "")

# Sauvegarder
saveRDS(df_enjeux_long, "/Users/adrien/Library/CloudStorage/Dropbox/travail/opubliq/substack_elxn_mtl/data/processed/saillance_enjeux.rds")

################### Section 4 ############################
############## GRAPHIQUES PRINCIPAUX #############

library(ggplot2)
library(dplyr)

print("Étape 5: Création des graphiques...")

# Palette de couleurs pour les candidats
couleurs_candidats <- c(
  "martinez ferrada" = "#E74C3C",  # Rouge
  "rabouin" = "#3498DB",           # Bleu
  "sauve" = "#2ECC71",             # Vert
  "thibodeau" = "#F39C12",         # Orange
  "kacou" = "#9B59B6"              # Violet
)

# Palette de couleurs pour les enjeux
couleurs_enjeux <- c(
  "Coût des loyers / Accès à la propriété" = "#E74C3C",
  "Itinérance / Logement social" = "#E67E22",
  "Congestion routière / Chantiers" = "#F39C12",
  "Transport collectif" = "#3498DB",
  "Sécurité / Criminalité" = "#9B59B6",
  "Taxes" = "#1ABC9C",
  "Propreté / Déneigement / Services publics" = "#2ECC71",
  "Infrastructures de transport" = "#34495E",
  "Développement économique" = "#16A085",
  "Changements climatiques" = "#27AE60",
  "Transport actif" = "#F1C40F",
  "Langue française" = "#E91E63",
  "Bureaucratie / Réglementation" = "#95A5A6"
)

## GRAPHIQUE 1A: Candidats - Médias FRANCOPHONES ##

# Filtrer pour garder seulement les 5 candidats principaux
candidats_principaux <- c("martinez ferrada", "rabouin", "sauve", "thibodeau", "kacou")

df_candidats_fr <- df_candidats_long %>%
  filter(region == "MTL_QC",
         candidats_mentionnes %in% candidats_principaux) %>%
  group_by(date, candidats_mentionnes) %>%
  summarise(indice_absolu = sum(indice_absolu), .groups = "drop")

p1a <- ggplot(df_candidats_fr, aes(x = date, y = indice_absolu,
                                   color = candidats_mentionnes,
                                   group = candidats_mentionnes)) +
  geom_line(size = 1.5, alpha = 0.8) +
  geom_point(size = 3.5) +
  scale_x_date(date_breaks = "1 week", date_labels = "%d %b") +
  scale_color_manual(
    values = couleurs_candidats,
    labels = c("Martinez Ferrada", "Rabouin", "Sauvé", "Thibodeau", "Kacou"),
    name = "Candidat"
  ) +
  labs(
    title = "Saillance médiatique des candidats - Médias francophones",
    subtitle = "Élection municipale de Montréal 2025",
    x = "",
    y = "Indice de saillance médiatique",
    caption = "Source: La Presse, Le Devoir, JDM, TVA, Radio-Canada (10 sept - 3 nov 2025)"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "right",
    legend.title = element_text(face = "bold", size = 14),
    legend.text = element_text(size = 12),
    axis.title.y = element_text(size = 15, face = "bold"),
    axis.text = element_text(size = 12),
    axis.text.x = element_text(angle = 45, hjust = 1),
    plot.title = element_text(size = 20, face = "bold", hjust = 0),
    plot.subtitle = element_text(size = 13, color = "gray30"),
    plot.caption = element_text(size = 10, color = "gray50", hjust = 0),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "gray90")
  )

ggsave("/Users/adrien/Library/CloudStorage/Dropbox/travail/opubliq/substack_elxn_mtl/output/figures/candidats_francophones.png",
       p1a, width = 14, height = 9, dpi = 300)
print("✓ Graphique 1A créé: candidats_francophones.png")

## GRAPHIQUE 1B: Candidats - Médias ANGLOPHONES ##

df_candidats_en <- df_candidats_long %>%
  filter(region == "MTL_EN",
         candidats_mentionnes %in% candidats_principaux) %>%
  group_by(date, candidats_mentionnes) %>%
  summarise(indice_absolu = sum(indice_absolu), .groups = "drop")

p1b <- ggplot(df_candidats_en, aes(x = date, y = indice_absolu,
                                   color = candidats_mentionnes,
                                   group = candidats_mentionnes)) +
  geom_line(size = 1.5, alpha = 0.8) +
  geom_point(size = 3.5) +
  scale_x_date(date_breaks = "1 week", date_labels = "%d %b") +
  scale_color_manual(
    values = couleurs_candidats,
    labels = c("Martinez Ferrada", "Rabouin", "Sauvé", "Thibodeau", "Kacou"),
    name = "Candidat"
  ) +
  labs(
    title = "Saillance médiatique des candidats - Médias anglophones",
    subtitle = "Élection municipale de Montréal 2025",
    x = "",
    y = "Indice de saillance médiatique",
    caption = "Source: Montreal Gazette, CBC Montreal, CTV Montreal (10 sept - 3 nov 2025)"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "right",
    legend.title = element_text(face = "bold", size = 14),
    legend.text = element_text(size = 12),
    axis.title.y = element_text(size = 15, face = "bold"),
    axis.text = element_text(size = 12),
    axis.text.x = element_text(angle = 45, hjust = 1),
    plot.title = element_text(size = 20, face = "bold", hjust = 0),
    plot.subtitle = element_text(size = 13, color = "gray30"),
    plot.caption = element_text(size = 10, color = "gray50", hjust = 0),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "gray90")
  )

ggsave("/Users/adrien/Library/CloudStorage/Dropbox/travail/opubliq/substack_elxn_mtl/output/figures/candidats_anglophones.png",
       p1b, width = 14, height = 9, dpi = 300)
print("✓ Graphique 1B créé: candidats_anglophones.png")

## GRAPHIQUE 1C: Candidats - TOUS LES MÉDIAS ##

df_candidats_all <- df_candidats_long %>%
  filter(candidats_mentionnes %in% candidats_principaux) %>%
  group_by(date, candidats_mentionnes) %>%
  summarise(indice_absolu = sum(indice_absolu), .groups = "drop")

p1c <- ggplot(df_candidats_all, aes(x = date, y = indice_absolu,
                                   color = candidats_mentionnes,
                                   group = candidats_mentionnes)) +
  geom_line(size = 1.5, alpha = 0.8) +
  geom_point(size = 3.5) +
  scale_x_date(date_breaks = "1 week", date_labels = "%d %b") +
  scale_color_manual(
    values = couleurs_candidats,
    labels = c("Martinez Ferrada", "Rabouin", "Sauvé", "Thibodeau", "Kacou"),
    name = "Candidat"
  ) +
  labs(
    title = "Saillance médiatique des candidats - Tous les médias montréalais",
    subtitle = "Élection municipale de Montréal 2025",
    x = "",
    y = "Indice de saillance médiatique",
    caption = "Source: Tous les médias montréalais (francophones et anglophones, 10 sept - 3 nov 2025)"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "right",
    legend.title = element_text(face = "bold", size = 14),
    legend.text = element_text(size = 12),
    axis.title.y = element_text(size = 15, face = "bold"),
    axis.text = element_text(size = 12),
    axis.text.x = element_text(angle = 45, hjust = 1),
    plot.title = element_text(size = 20, face = "bold", hjust = 0),
    plot.subtitle = element_text(size = 13, color = "gray30"),
    plot.caption = element_text(size = 10, color = "gray50", hjust = 0),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "gray90")
  )

ggsave("/Users/adrien/Library/CloudStorage/Dropbox/travail/opubliq/substack_elxn_mtl/output/figures/candidats_tous_medias.png",
       p1c, width = 14, height = 9, dpi = 300)
print("✓ Graphique 1C créé: candidats_tous_medias.png")

## GRAPHIQUE 2A: Enjeux - Médias FRANCOPHONES ##

# Identifier les 8 enjeux les plus saillants (tous médias confondus)
top_enjeux <- df_enjeux_long %>%
  group_by(enjeux_mentionnes) %>%
  summarise(total = sum(indice_absolu)) %>%
  arrange(desc(total)) %>%
  head(8) %>%
  pull(enjeux_mentionnes)

df_enjeux_fr <- df_enjeux_long %>%
  filter(region == "MTL_QC",
         enjeux_mentionnes %in% top_enjeux) %>%
  group_by(date, enjeux_mentionnes) %>%
  summarise(indice_absolu = sum(indice_absolu), .groups = "drop")

p2a <- ggplot(df_enjeux_fr, aes(x = date, y = indice_absolu,
                                color = enjeux_mentionnes,
                                group = enjeux_mentionnes)) +
  geom_line(size = 1.5, alpha = 0.8) +
  geom_point(size = 3.5) +
  scale_x_date(date_breaks = "1 week", date_labels = "%d %b") +
  scale_color_manual(
    values = couleurs_enjeux,
    name = "Enjeu électoral"
  ) +
  labs(
    title = "Saillance des enjeux électoraux - Médias francophones",
    subtitle = "Élection municipale de Montréal 2025 - Top 8 des enjeux",
    x = "",
    y = "Indice de saillance médiatique",
    caption = "Source: La Presse, Le Devoir, JDM, TVA, Radio-Canada (10 sept - 3 nov 2025)"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "right",
    legend.title = element_text(face = "bold", size = 14),
    legend.text = element_text(size = 11),
    axis.title.y = element_text(size = 15, face = "bold"),
    axis.text = element_text(size = 12),
    axis.text.x = element_text(angle = 45, hjust = 1),
    plot.title = element_text(size = 20, face = "bold", hjust = 0),
    plot.subtitle = element_text(size = 13, color = "gray30"),
    plot.caption = element_text(size = 10, color = "gray50", hjust = 0),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "gray90"),
    legend.key.height = unit(1.2, "lines")
  ) +
  guides(color = guide_legend(ncol = 1))

ggsave("/Users/adrien/Library/CloudStorage/Dropbox/travail/opubliq/substack_elxn_mtl/output/figures/enjeux_francophones.png",
       p2a, width = 16, height = 9, dpi = 300)
print("✓ Graphique 2A créé: enjeux_francophones.png")

## GRAPHIQUE 2B: Enjeux - Médias ANGLOPHONES ##

df_enjeux_en <- df_enjeux_long %>%
  filter(region == "MTL_EN",
         enjeux_mentionnes %in% top_enjeux) %>%
  group_by(date, enjeux_mentionnes) %>%
  summarise(indice_absolu = sum(indice_absolu), .groups = "drop")

p2b <- ggplot(df_enjeux_en, aes(x = date, y = indice_absolu,
                                color = enjeux_mentionnes,
                                group = enjeux_mentionnes)) +
  geom_line(size = 1.5, alpha = 0.8) +
  geom_point(size = 3.5) +
  scale_x_date(date_breaks = "1 week", date_labels = "%d %b") +
  scale_color_manual(
    values = couleurs_enjeux,
    name = "Enjeu électoral"
  ) +
  labs(
    title = "Saillance des enjeux électoraux - Médias anglophones",
    subtitle = "Élection municipale de Montréal 2025 - Top 8 des enjeux",
    x = "",
    y = "Indice de saillance médiatique",
    caption = "Source: Montreal Gazette, CBC Montreal, CTV Montreal (10 sept - 3 nov 2025)"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "right",
    legend.title = element_text(face = "bold", size = 14),
    legend.text = element_text(size = 11),
    axis.title.y = element_text(size = 15, face = "bold"),
    axis.text = element_text(size = 12),
    axis.text.x = element_text(angle = 45, hjust = 1),
    plot.title = element_text(size = 20, face = "bold", hjust = 0),
    plot.subtitle = element_text(size = 13, color = "gray30"),
    plot.caption = element_text(size = 10, color = "gray50", hjust = 0),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "gray90"),
    legend.key.height = unit(1.2, "lines")
  ) +
  guides(color = guide_legend(ncol = 1))

ggsave("/Users/adrien/Library/CloudStorage/Dropbox/travail/opubliq/substack_elxn_mtl/output/figures/enjeux_anglophones.png",
       p2b, width = 16, height = 9, dpi = 300)
print("✓ Graphique 2B créé: enjeux_anglophones.png")

## GRAPHIQUE 2C: Enjeux - TOUS LES MÉDIAS ##

df_enjeux_all <- df_enjeux_long %>%
  filter(enjeux_mentionnes %in% top_enjeux) %>%
  group_by(date, enjeux_mentionnes) %>%
  summarise(indice_absolu = sum(indice_absolu), .groups = "drop")

p2c <- ggplot(df_enjeux_all, aes(x = date, y = indice_absolu,
                                color = enjeux_mentionnes,
                                group = enjeux_mentionnes)) +
  geom_line(size = 1.5, alpha = 0.8) +
  geom_point(size = 3.5) +
  scale_x_date(date_breaks = "1 week", date_labels = "%d %b") +
  scale_color_manual(
    values = couleurs_enjeux,
    name = "Enjeu électoral"
  ) +
  labs(
    title = "Saillance des enjeux électoraux - Tous les médias montréalais",
    subtitle = "Élection municipale de Montréal 2025 - Top 8 des enjeux",
    x = "",
    y = "Indice de saillance médiatique",
    caption = "Source: Tous les médias montréalais (francophones et anglophones, 10 sept - 3 nov 2025)"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "right",
    legend.title = element_text(face = "bold", size = 14),
    legend.text = element_text(size = 11),
    axis.title.y = element_text(size = 15, face = "bold"),
    axis.text = element_text(size = 12),
    axis.text.x = element_text(angle = 45, hjust = 1),
    plot.title = element_text(size = 20, face = "bold", hjust = 0),
    plot.subtitle = element_text(size = 13, color = "gray30"),
    plot.caption = element_text(size = 10, color = "gray50", hjust = 0),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "gray90"),
    legend.key.height = unit(1.2, "lines")
  ) +
  guides(color = guide_legend(ncol = 1))

ggsave("/Users/adrien/Library/CloudStorage/Dropbox/travail/opubliq/substack_elxn_mtl/output/figures/enjeux_tous_medias.png",
       p2c, width = 16, height = 9, dpi = 300)
print("✓ Graphique 2C créé: enjeux_tous_medias.png")

################### Section 5 ############################
############## Tableaux récapitulatifs #############

# Récapitulatif candidats - Par région (5 candidats principaux seulement)
recap_candidats_par_region <- df_candidats_long %>%
  filter(candidats_mentionnes %in% candidats_principaux) %>%
  group_by(region, candidats_mentionnes) %>%
  summarise(
    n_mentions = sum(n),
    indice_total = sum(indice_absolu),
    n_jours = n_distinct(date),
    .groups = "drop"
  ) %>%
  group_by(region) %>%
  mutate(
    pct_saillance = round(100 * indice_total / sum(indice_total), 1)
  ) %>%
  arrange(region, desc(indice_total)) %>%
  mutate(
    candidats_mentionnes = str_to_title(candidats_mentionnes),
    region = case_when(
      region == "MTL_QC" ~ "Francophones",
      region == "MTL_EN" ~ "Anglophones",
      TRUE ~ region
    )
  )

# Récapitulatif candidats - Tous médias (5 candidats principaux seulement)
recap_candidats_total <- df_candidats_long %>%
  filter(candidats_mentionnes %in% candidats_principaux) %>%
  group_by(candidats_mentionnes) %>%
  summarise(
    n_mentions = sum(n),
    indice_total = sum(indice_absolu),
    n_jours = n_distinct(date)
  ) %>%
  arrange(desc(indice_total)) %>%
  mutate(
    candidats_mentionnes = str_to_title(candidats_mentionnes),
    pct_saillance = round(100 * indice_total / sum(indice_total), 1)
  )

print("")
print("========================================")
print("RÉCAPITULATIF: SAILLANCE DES CANDIDATS")
print("========================================")
print("")
print("Par type de média:")
print(recap_candidats_par_region)
print("")
print("Tous médias confondus:")
print(recap_candidats_total)

# Récapitulatif enjeux - Par région
recap_enjeux_par_region <- df_enjeux_long %>%
  group_by(region, enjeux_mentionnes) %>%
  summarise(
    n_mentions = sum(n),
    indice_total = sum(indice_absolu),
    n_jours = n_distinct(date),
    .groups = "drop"
  ) %>%
  group_by(region) %>%
  mutate(
    pct_saillance = round(100 * indice_total / sum(indice_total), 1)
  ) %>%
  arrange(region, desc(indice_total)) %>%
  mutate(
    region = case_when(
      region == "MTL_QC" ~ "Francophones",
      region == "MTL_EN" ~ "Anglophones",
      TRUE ~ region
    )
  ) %>%
  group_by(region) %>%
  slice_head(n = 10) %>%
  ungroup()

# Récapitulatif enjeux - Tous médias
recap_enjeux_total <- df_enjeux_long %>%
  group_by(enjeux_mentionnes) %>%
  summarise(
    n_mentions = sum(n),
    indice_total = sum(indice_absolu),
    n_jours = n_distinct(date)
  ) %>%
  arrange(desc(indice_total)) %>%
  mutate(
    pct_saillance = round(100 * indice_total / sum(indice_total), 1)
  ) %>%
  head(10)

print("")
print("========================================")
print("RÉCAPITULATIF: TOP 10 ENJEUX")
print("========================================")
print("")
print("Par type de média:")
print(recap_enjeux_par_region)
print("")
print("Tous médias confondus:")
print(recap_enjeux_total)

# Sauvegarder les récapitulatifs
write_csv(recap_candidats_par_region, "/Users/adrien/Library/CloudStorage/Dropbox/travail/opubliq/substack_elxn_mtl/data/outputs/recap_candidats_par_region.csv")
write_csv(recap_candidats_total, "/Users/adrien/Library/CloudStorage/Dropbox/travail/opubliq/substack_elxn_mtl/data/outputs/recap_candidats_total.csv")
write_csv(recap_enjeux_par_region, "/Users/adrien/Library/CloudStorage/Dropbox/travail/opubliq/substack_elxn_mtl/data/outputs/recap_enjeux_par_region.csv")
write_csv(recap_enjeux_total, "/Users/adrien/Library/CloudStorage/Dropbox/travail/opubliq/substack_elxn_mtl/data/outputs/recap_enjeux_total.csv")

toc()
beep()

print("")
print("============================================================")
print("ANALYSE TERMINÉE!")
print("============================================================")
print("")
print("📊 GRAPHIQUES CRÉÉS (6 au total):")
print("")
print("  CANDIDATS:")
print("    ✓ candidats_francophones.png")
print("    ✓ candidats_anglophones.png")
print("    ✓ candidats_tous_medias.png")
print("")
print("  ENJEUX:")
print("    ✓ enjeux_francophones.png")
print("    ✓ enjeux_anglophones.png")
print("    ✓ enjeux_tous_medias.png")
print("")
print("💾 DONNÉES SAUVEGARDÉES:")
print("  - candidats_enjeux_extraction.rds (extraction complète)")
print("  - saillance_candidats.rds")
print("  - saillance_enjeux.rds")
print("")
print("📈 RÉCAPITULATIFS CSV:")
print("  - recap_candidats_par_region.csv")
print("  - recap_candidats_total.csv")
print("  - recap_enjeux_par_region.csv")
print("  - recap_enjeux_total.csv")
print("============================================================")

