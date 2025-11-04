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

df <- readRDS("/Users/adriencloutier/Library/CloudStorage/Dropbox/Travail/Universite_Laval/Ellipse/vitrine/data/saillance_personnalites.rds")

# Voir quand les dernières données ont été collectées
# c <- tube::ellipse_connect("PROD", "datawarehouse")
# tables <- tube::ellipse_discover(c)

set.seed(42)

# Lancer le chrono
tic("Temps d'exécution total")

# Charger les données locales depuis AWS
con <- ellipse_connect("PROD")

# Définir les bornes temporelles pour l'analyse
borne_inf <- ymd_hms("2025-01-01 12:00:00", tz = "America/Toronto")
borne_sup <- ymd_hms("2025-03-15 00:00:00", tz = "America/Toronto")

# On va s'intéresser aux Unes médiatiques 🗞️
df_local <- ellipse_query(con, "r-media-headlines") |>
  filter(extraction_year == 2025,
         extraction_month %in% 01:04)|>
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
#  filter(media_id %in% c("TVA", "JDM", "LAP", "RCI", "LED", "CBC", "CTV", "GAM", "GN", "NP", "TTS", "VS"))

# Enfin, on peut nettoyer les titres et les textes
to_remove <- "\\||CTV News|JDM|La Presse|Le Devoir|Radio-Canada|Radio-Canada Info|TVA Nouvelles|RCI|CBC|Global News|GAM|GN|NP|TTS|VS|FXN|CNN|The Star|Montreal Gazette|National Post|The Globe and Mail|Fox News fox news"

# Nettoyage des titres et des textes
df_clean <- df_headline_duration |>
  mutate(
    title = stringr::str_remove_all(title, to_remove) |> stringr::str_squish(),
    body = stringr::str_remove_all(body, to_remove) |> stringr::str_squish(),  # Nettoyage des textes
    langue = case_when(
      media_id %in% c("JDM", "LED", "TVA", "LAP", "RCI", "MG") ~ "fr",
      media_id %in% c("CBC", "CTV", "VS", "GN", "NP", "GAM", "TTS", "FXN", "CNN") ~ "en",
      TRUE ~ "autre"  # Sécurité
    ),
    pays = case_when(
      media_id %in% c("JDM", "LED", "TVA", "LAP", "RCI", "MG") ~ "QC",
      media_id %in% c("CBC", "CTV", "VS", "GN", "NP", "GAM", "TTS") ~ "CAN",
      media_id %in% c("CNN", "FXN") ~ "USA",
      TRUE ~ "Autre"
    )
  )

################### Section 2 ############################
############## Extraire les objets saillants #############

model_to_use <- "gpt-4o-mini"  # Changer ici le modèle (https://platform.openai.com/docs/models)

df_objects <- df_clean %>%
  rowwise() %>%
  mutate(
    prompt = glue("
      Voici un article provenant d'un média {ifelse(langue == 'fr', 'francophone', 'anglophone')}.
      **Titre :** {title}
      **Extrait :** ```{body}```

      Identifie les 5 objets principaux qui s'y retrouvent (événements, personnes, lieux, organisations, concepts clés, etc.).
      Crée une liste de ces objets séparés par des virgules.
      Autant pour les médias francophones qu'anglophones, sors tous les objets en anglais.

      **Consignes particulières :**
      - **Apprend de chaque article précédemment traités pour produire, dans la mesure du possible, la même formulation pour un même objet.**
      Par exemple :
        - Si tu extrait l'objet **'donald trump'** via des premiers articles, continue d'utiliser cette formulation si l'objet
        se trouve dans d'autres articles, plutôt que de créer un autre objet comme 'president donald trump' ou 'trump'.
      - **Priorise les objets présents dans le titre, s'ils sont aussi mentionnés dans le texte.**
      - **Garde les objets courts et précis.** Pas de phrases longues ni d'expressions inutiles.
      - **Supprime la ponctuation inutile.**
      - Ne crée pas trop d'objets, surtout s'ils ne sont pas «saillants» dans le contexte de l'article.
      Extrait seulement les 5 objets saillants qui permettent de résumer parfaitement les éléments importants de l'article.
    "),

    # Création de la conversation
    conversation = list(openai_create_conversation(
      user_message = prompt,
      system_message = "Tu es un journaliste expert en extraction de personnes saillantes des articles d'actualité.
      Tu excelles à identifier ce qui se passe dans l’article et à extraire les personnes qui représentent l’actualité rapportée."
    )),

    # Envoi de la requête à OpenAI
    response = list(openai_chat_completion(messages = conversation, model = model_to_use)),

    # Extraction des objets saillants
    extracted_objects = response$content
  ) %>%
  ungroup()

#saveRDS(df_objects, "/Users/adriencloutier/Library/CloudStorage/Dropbox/Travail/Universite_Laval/Ellipse/vitrine/data/saillance_personnalites.rds")

toc()

# ################### Section 3 ############################
# ############## Regrouper les concepts #############
#
# ## 2e boucle AI pour créer des regroupements d'objets d'un plus haut niveau d'abstraction
#
# df_long <- df_objects %>%
#   separate_rows(extracted_objects, sep = ",") %>%  # Sépare les objets en plusieurs lignes
#   rename(objets = extracted_objects) %>%
#   rowwise() %>%
#   mutate(
#     prompt_regroupement = glue("
#       Voici un objet extrait d'un article d'actualité : \"{objets}\".
#       Ton objectif est d'identifier s'il peut être standardisé avec d'autres objets présents dans la base de données.
#
#       **Instructions :**
#       - Si l'objet correspond déjà à une formulation claire et standard, garde-le tel quel.
#       - Si plusieurs objets similaires existent, regroupe-les sous un seul terme générique.
#       - Uniformise le singulier ou le pluriel.
#       - **Quelques exemples du travail que tu dois réaliser :**
#         - *'donald trump', 'trump', 'administration trump', 'président trump'*: standardisé à 'donald trump'
#         - *'b.c. government', 'government of british columbia'*: standardisé à 'gouvernement de la colombie-britannique'
#         - *'accord canada-united states-mexico', 'accord canada-united states-mexico (cusma)'*: standardisé à 'accord de libre-échange nord-américain'
#       - Ne change pas complètement les objets. Par exemple, 'acier' ne doit pas devenir 'métaux'.
#       - Retourne uniquement l’objet standardisé, sans autre explication.
#       - Assure-toi que tous les objets soient dans la même langue: l'anglais.
#
#
#       Objet extrait : \"{objets}\"
#     "),
#
#     conversation_regroupement = list(openai_create_conversation(
#       user_message = prompt_regroupement,
#       system_message = "Tu es un expert en classification et harmonisation des objets d'actualité.
#       Tu dois standardiser les objets qui peuvent l'être pour les regrouper et éviter les formulations alternatives inutiles."
#     )),
#
#     response_regroupement = list(openai_chat_completion(messages = conversation_regroupement, model = model_to_use)),
#
#     objet_reference = response_regroupement$content  # Extraction de l’objet harmonisé
#   ) %>%
#   mutate(
#     objet_reference = tolower(trimws(objet_reference)),  # Normalisation
#     objet_reference = str_remove_all(objet_reference, "[[:punct:]]")  # Suppression de la ponctuation
#   ) %>%
#   filter(!is.na(objet_reference) & objet_reference != "") %>%
#   ungroup()

################### Section 4 ############################
############## Calculer les indices de saillance #############

df_long <- df_objects %>%
  mutate(date = as.Date(headline_start)) %>%
  separate_rows(extracted_objects, sep = ",") %>%  # Sépare les objets en plusieurs lignes
  mutate(
    extracted_objects = tolower(trimws(extracted_objects)),  # Normalisation
    extracted_objects = str_remove_all(extracted_objects, "[[:punct:]]")  # Suppression de la ponctuation
  ) %>%
  group_by(pays, date, extracted_objects) %>%
  summarise(
    n = n(),  # Nombre d'occurrences de l'objet
    total_minutes_objet = sum(headline_minutes, na.rm = TRUE),  # Somme du temps en Une
    urls = list(unique(url)),  # Stocker les URLs uniques
    titres = list(unique(title)),  # Stocker les titres uniques
    bodies = list(unique(body)),  # Stocker les textes complets des articles
    .groups = "drop"
  ) %>%
  group_by(pays, date, extracted_objects) %>%
  mutate(indice_absolu = n * total_minutes_objet) %>%
  group_by(pays, date) %>%
  mutate(total_absolu = sum(indice_absolu),
         indice_relatif = indice_absolu / total_absolu,  # Score relatif pondéré
         n_titles = map_int(titres, length),
         n_bodies = map_int(bodies, length)
  ) %>%
  arrange(pays, desc(indice_absolu)  # Trier selon l'importance
) %>%
  filter(!is.na(extracted_objects) & extracted_objects != "") %>%
  ungroup()

################### Section 5 ############################
############## Créer le graphique #############

library(ggplot2)
library(dplyr)
library(ggrepel)

# Filtrer pour CAN
df_can <- df_long %>%
  filter(pays == "CAN", extracted_objects != "canada") %>%
  group_by(date) %>%
  arrange(desc(indice_absolu)) %>%
  slice(1) %>% # Sélection stricte du top 5 par jour
  ungroup()

ggplot(df_can, aes(x = date, y = indice_absolu, color = extracted_objects, group = extracted_objects)) +
  geom_line(size = 1) +  # Ajouter les lignes reliant les points
  geom_point(size = 4) +  # Points plus grands
  geom_text_repel(
    aes(label = extracted_objects),
    size = 4,  # Taille des labels
    max.overlaps = 100,  # Augmenter pour éviter la suppression des labels
    show.legend = FALSE
  ) +
  scale_x_date(date_breaks = "1 weeks", date_labels = "%d %b") +
  scale_color_viridis_d() +
  labs(
    title = "Objet le plus saillant chaque jour au Canada en 2025",
    x = "",
    y = "Indice absolu\n",
    color = "Objets"
  ) +
  theme_minimal(base_size = 16) +
  theme(
    legend.position = "none",
    axis.title = element_text(size = 18),
    axis.text = element_text(size = 14),
    plot.title = element_text(size = 20, face = "bold")
  )

######

# Filtrer pour USA
df_usa <- df_long %>%
  filter(pays == "USA") %>%
  group_by(date) %>%
  arrange(desc(indice_absolu)) %>%
  slice(1) %>% # Sélection stricte du top 5 par jour
  ungroup()

ggplot(df_usa, aes(x = date, y = indice_absolu, color = extracted_objects, group = extracted_objects)) +
  geom_line(size = 1) +  # Ajouter les lignes reliant les points
  geom_point(size = 4) +  # Points plus grands
  geom_text_repel(
    aes(label = extracted_objects),
    size = 4,  # Taille des labels
    max.overlaps = 100,  # Augmenter pour éviter la suppression des labels
    show.legend = FALSE
  ) +
  scale_x_date(date_breaks = "1 weeks", date_labels = "%d %b") +
  scale_color_viridis_d() +
  labs(
    title = "Objet le plus saillant chaque jour aux États-Unis en 2025",
    x = "",
    y = "Indice absolu\n",
    color = "Objets"
  ) +
  theme_minimal(base_size = 16) +
  theme(
    legend.position = "none",
    axis.title = element_text(size = 18),
    axis.text = element_text(size = 14),
    plot.title = element_text(size = 20, face = "bold")
  )

#####

# Filtrer pour USA
df_qc <- df_long %>%
  filter(pays == "QC", extracted_objects != "québec", extracted_objects != "montréal") %>%
  group_by(date) %>%
  arrange(desc(indice_absolu)) %>%
  slice(1) %>% # Sélection stricte du top 5 par jour
  ungroup()

ggplot(df_qc, aes(x = date, y = indice_absolu, color = extracted_objects, group = extracted_objects)) +
  geom_line(size = 1) +  # Ajouter les lignes reliant les points
  geom_point(size = 4) +  # Points plus grands
  geom_text_repel(
    aes(label = extracted_objects),
    size = 4,  # Taille des labels
    max.overlaps = 100,  # Augmenter pour éviter la suppression des labels
    show.legend = FALSE
  ) +
  scale_x_date(date_breaks = "1 weeks", date_labels = "%d %b") +
  scale_color_viridis_d() +
  labs(
    title = "Objet le plus saillant chaque jour au Québec en 2025",
    x = "",
    y = "Indice absolu\n",
    color = "Objets"
  ) +
  theme_minimal(base_size = 16) +
  theme(
    legend.position = "none",
    axis.title = element_text(size = 18),
    axis.text = element_text(size = 14),
    plot.title = element_text(size = 20, face = "bold")
  )

#######

# Filtrer pour CAN et ne garder que les personnalités spécifiques
df_personnalites_can <- df_long %>%
  filter(
    pays == "CAN",
    extracted_objects %in% c("pierre poilievre", "justin trudeau", "donald trump", "mark carney")
  ) %>%
  group_by(date, extracted_objects) %>%
  summarise(indice_absolu = sum(indice_absolu), .groups = "drop")  # Somme de la saillance pour chaque jour et personne

# Graphique de l'évolution de la saillance
ggplot(df_personnalites_can, aes(x = date, y = indice_absolu, color = extracted_objects, group = extracted_objects)) +
  geom_line(size = 1.2) +  # Lignes plus épaisses pour la visibilité
  geom_point(size = 3) +  # Points pour marquer chaque valeur
  scale_x_date(date_breaks = "2 weeks", date_labels = "%d %b") +  # Affichage des dates toutes les 2 semaines
  scale_color_manual(values = c("blue", "red", "orange", "purple")) +  # Couleurs distinctes pour chaque personnalité
  labs(
    title = "Évolution de la saillance médiatique de personnalités au Canada en 2025",
    x = "",
    y = "Indice absolu",
    color = "Personnalités"
  ) +
  theme_minimal(base_size = 16) +
  theme(
    legend.position = "right",
    axis.title = element_text(size = 18),
    axis.text = element_text(size = 14),
    plot.title = element_text(size = 20, face = "bold")
  )

#####

# Filtrer pour CAN et ne garder que les personnalités spécifiques
df_personnalites_qc <- df_long %>%
  filter(
    pays == "QC",
    extracted_objects %in% c("pierre poilievre", "mark carney")
  ) %>%
  group_by(date, extracted_objects) %>%
  summarise(indice_absolu = sum(indice_absolu), .groups = "drop")  # Somme de la saillance pour chaque jour et personne

# Graphique de l'évolution de la saillance
ggplot(df_personnalites_qc, aes(x = date, y = indice_absolu, color = extracted_objects, group = extracted_objects)) +
  geom_line(size = 1.2) +  # Lignes plus épaisses pour la visibilité
  geom_point(size = 3) +  # Points pour marquer chaque valeur
  scale_x_date(date_breaks = "2 weeks", date_labels = "%d %b") +  # Affichage des dates toutes les 2 semaines
  scale_color_manual(values = c("orange", "purple")) +  # Couleurs distinctes pour chaque personnalité
  labs(
    title = "Évolution de la saillance médiatique de personnalités au Québec en 2025",
    x = "",
    y = "Indice absolu",
    color = "Personnalités"
  ) +
  theme_minimal(base_size = 16) +
  theme(
    legend.position = "right",
    axis.title = element_text(size = 18),
    axis.text = element_text(size = 14),
    plot.title = element_text(size = 20, face = "bold")
  )

####
