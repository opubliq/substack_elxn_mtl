# ==============================================================================
# MEDIA SALIENCE TIMELINE VISUALIZATION - Montreal Municipal Election 2025
# ==============================================================================
#
# Creates faceted timeline showing media salience trends for each candidate
# with comparative lines (similar style to polls_timeline.R)
#
# ==============================================================================

# Load libraries ---------------------------------------------------------------
library(dplyr)
library(tidyr)
library(ggplot2)
library(lubridate)

# Load data --------------------------------------------------------------------
media_salience <- readRDS("data/processed/media_salience_daily.rds")

# Define color palette (same as polls_timeline.R) -----------------------------
candidate_colors <- c(
  "soraya_martinez_ferrada" = "#b344b1",
  "luc_rabouin" = "#009076",
  "craig_sauve" = "#fa8c00",
  "gilbert_thibodeau" = "#15607a",
  "jf_kacou" = "#18a1cd",
  "indecis" = "#808080"
)

# Define proper names with accents (same as polls_timeline.R) -----------------
candidate_labels <- c(
  "soraya_martinez_ferrada" = "Soraya Martinez Ferrada",
  "luc_rabouin" = "Luc Rabouin",
  "craig_sauve" = "Craig Sauvé",
  "gilbert_thibodeau" = "Gilbert Thibodeau",
  "jf_kacou" = "J.-F. Kacou",
  "indecis" = "Indécis"
)

# Prepare data for visualization -----------------------------------------------
# Convert from wide to long format
media_long <- media_salience %>%
  select(-election) %>%  # Handle election separately
  pivot_longer(
    cols = -date,
    names_to = "candidat",
    values_to = "salience"
  ) %>%
  mutate(
    # Add proper names
    candidat_label = candidate_labels[candidat],
    # Convert to percentage for consistency with polls
    salience_pct = salience * 100
  )

# Find order based on last day's salience --------------------------------------
last_date <- max(media_long$date)
candidate_order <- media_long %>%
  filter(date == last_date) %>%
  arrange(desc(salience_pct)) %>%
  pull(candidat_label)

# Move "Indécis" to the end, regardless of ranking
candidate_order <- c(
  setdiff(candidate_order, "Indécis"),
  "Indécis"
)

# Set factor levels for ordering
media_long <- media_long %>%
  mutate(candidat_label = factor(candidat_label, levels = candidate_order))

# Create faceted data: for each facet, mark which candidate is highlighted ----
media_faceted <- media_long %>%
  # Create a version for each facet
  tidyr::crossing(facet_candidate = unique(media_long$candidat_label)) %>%
  mutate(
    is_highlighted = (candidat_label == facet_candidate),
    color = candidate_colors[candidat],
    alpha = ifelse(is_highlighted, 1, 0.2),
    linewidth = ifelse(is_highlighted, 1.2, 0.5)
  )

# Create the faceted timeline plot ---------------------------------------------
p_facet <- ggplot() +
  # Add all candidate lines
  geom_line(
    data = media_faceted,
    aes(x = date, y = salience_pct, color = candidat,
        linewidth = is_highlighted, alpha = is_highlighted, group = candidat),
    show.legend = FALSE
  ) +
  # Facet by candidate (using proper names)
  facet_wrap(~ facet_candidate, ncol = 2) +
  # Apply color scales
  scale_color_manual(values = candidate_colors) +
  scale_linewidth_manual(values = c(`FALSE` = 0.5, `TRUE` = 1.2)) +
  scale_alpha_manual(values = c(`FALSE` = 0.2, `TRUE` = 1)) +
  # Format axes
  scale_x_date(
    date_labels = "%d %b",
    date_breaks = "1 week"
  ) +
  scale_y_continuous(
    labels = function(x) paste0(x, "%"),
    limits = c(0, NA)
  ) +
  # Labels
  labs(
    title = "Évolution de la saillance médiatique - Élection municipale Montréal 2025",
    subtitle = "Indice de saillance quotidienne (0-100%)",
    y = "Saillance médiatique (%)\\n"
  ) +
  # Theme
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 10, color = "grey40"),
    strip.text = element_text(face = "bold", size = 10),
    strip.background = element_rect(fill = "grey95", color = NA),
    panel.grid.minor = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

print(p_facet)

# Save faceted plot ------------------------------------------------------------
dir.create("output/figures", showWarnings = FALSE, recursive = TRUE)

ggsave(
  "output/figures/media_salience_timeline_facet.png",
  plot = p_facet,
  width = 12,
  height = 10,
  dpi = 300,
  bg = "white"
)

cat("\nGraphique avec facets sauvegardé: output/figures/media_salience_timeline_facet.png\n")


# ==============================================================================
# COMBINED PLOT - All candidates on one graph
# ==============================================================================

# Add election salience overlay data -------------------------------------------
election_overlay <- media_salience %>%
  select(date, election) %>%
  mutate(election_pct = election * 100)

p_combined <- ggplot(media_long, aes(x = date, y = salience_pct, color = candidat_label)) +
  # Add election salience as shaded area in background
  geom_area(
    data = election_overlay,
    aes(x = date, y = election_pct),
    inherit.aes = FALSE,
    fill = "grey85",
    alpha = 0.5
  ) +
  # Add label for election area
  annotate(
    "text",
    x = min(media_long$date) + days(3),
    y = max(election_overlay$election_pct) * 0.95,
    label = "Saillance générale\nde l'élection",
    color = "grey50",
    size = 3.5,
    hjust = 0,
    fontface = "italic",
    lineheight = 0.9
  ) +
  # Add lines for candidates
  geom_line(linewidth = 1.2) +
  # Apply color scales (map candidate_label to candidat colors)
  scale_color_manual(
    values = setNames(candidate_colors, candidate_labels),
    name = NULL
  ) +
  # Format axes
  scale_x_date(
    date_labels = "%d %b",
    date_breaks = "1 week"
  ) +
  scale_y_continuous(
    labels = function(x) paste0(x, "%"),
    limits = c(0, NA)
  ) +
  # Labels
  labs(
    title = "Évolution de la saillance médiatique - Élection municipale Montréal 2025",
    subtitle = "Tous les candidats (zone grise = saillance générale de l'élection)",
    y = "Saillance médiatique (%)\\n"
  ) +
  # Theme
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11, color = "grey40"),
    legend.position = "right",
    legend.text = element_text(size = 10),
    panel.grid.minor = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

print(p_combined)

# Save combined plot -----------------------------------------------------------
ggsave(
  "output/figures/media_salience_timeline_combined.png",
  plot = p_combined,
  width = 12,
  height = 7,
  dpi = 300,
  bg = "white"
)

cat("Graphique combiné sauvegardé: output/figures/media_salience_timeline_combined.png\n")


# ==============================================================================
# CORRELATION PLOT - Media salience vs poll dates
# ==============================================================================

# Load polls for comparison
polls <- readRDS("data/processed/polls.rds")

# Get poll dates
poll_dates <- polls %>%
  distinct(poll_id, date_debut, date_fin) %>%
  mutate(poll_midpoint = date_debut + (date_fin - date_debut) / 2)

# Create plot with poll markers
p_with_polls <- ggplot(media_long, aes(x = date, y = salience_pct, color = candidat_label)) +
  # Add vertical lines for poll dates
  geom_vline(
    data = poll_dates,
    aes(xintercept = poll_midpoint),
    linetype = "dashed",
    color = "grey60",
    alpha = 0.5
  ) +
  # Add poll labels
  geom_text(
    data = poll_dates,
    aes(x = poll_midpoint, y = Inf, label = poll_id),
    inherit.aes = FALSE,
    angle = 90,
    hjust = 1.1,
    vjust = -0.3,
    size = 3,
    color = "grey50",
    fontface = "bold"
  ) +
  # Add lines for candidates
  geom_line(linewidth = 1.2) +
  # Apply color scales
  scale_color_manual(
    values = setNames(candidate_colors, candidate_labels),
    name = NULL
  ) +
  # Format axes
  scale_x_date(
    date_labels = "%d %b",
    date_breaks = "1 week"
  ) +
  scale_y_continuous(
    labels = function(x) paste0(x, "%"),
    limits = c(0, NA),
    expand = expansion(mult = c(0, 0.1))
  ) +
  # Labels
  labs(
    title = "Saillance médiatique et dates de sondages",
    subtitle = "Lignes verticales = publication des sondages",
    y = "Saillance médiatique (%)\\n"
  ) +
  # Theme
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(size = 11, color = "grey40"),
    legend.position = "right",
    legend.text = element_text(size = 10),
    panel.grid.minor = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

print(p_with_polls)

# Save poll correlation plot ---------------------------------------------------
ggsave(
  "output/figures/media_salience_with_polls.png",
  plot = p_with_polls,
  width = 12,
  height = 7,
  dpi = 300,
  bg = "white"
)

cat("Graphique avec dates de sondages sauvegardé: output/figures/media_salience_with_polls.png\n")

cat("\n=== VISUALIZATIONS COMPLETE ===\n")
