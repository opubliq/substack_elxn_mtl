# ==============================================================================
# POLLS TIMELINE VISUALIZATION - Montreal Municipal Election 2025
# ==============================================================================
#
# Creates a faceted timeline showing polling trends for each candidate
# with margin of error bands and comparative lines
#
# ==============================================================================

# Load libraries ---------------------------------------------------------------
library(dplyr)
library(ggplot2)
library(lubridate)
library(stringr)

# Load data --------------------------------------------------------------------
polls <- readRDS("data/processed/polls.rds")

# Define color palette ---------------------------------------------------------
candidate_colors <- c(
  "soraya_martinez_ferrada" = "#b344b1",
  "luc_rabouin" = "#009076",
  "craig_sauve" = "#fa8c00",
  "gilbert_thibodeau" = "#15607a",
  "jf_kacou" = "#18a1cd",
  "indecis" = "#808080"
)

# Define proper names with accents ---------------------------------------------
candidate_labels <- c(
  "soraya_martinez_ferrada" = "Soraya Martinez Ferrada",
  "luc_rabouin" = "Luc Rabouin",
  "craig_sauve" = "Craig Sauvé",
  "gilbert_thibodeau" = "Gilbert Thibodeau",
  "jf_kacou" = "J.-F. Kacou",
  "indecis" = "Indécis"
)

# Prepare data for visualization -----------------------------------------------
polls_viz <- polls %>%
  mutate(
    # Calculate confidence interval bounds for ribbon
    vote_pct = vote_intention * 100,
    lower = (vote_intention - marge_erreur) * 100,
    upper = (vote_intention + marge_erreur) * 100,
    # Ensure bounds stay within 0-100%
    lower = pmax(0, lower),
    upper = pmin(100, upper),
    # Add proper names
    candidat_label = candidate_labels[candidat]
  )

# Find order based on last poll ------------------------------------------------
last_poll_date <- max(polls_viz$date_fin)
candidate_order <- polls_viz %>%
  filter(date_fin == last_poll_date) %>%
  arrange(desc(vote_pct)) %>%
  pull(candidat_label)

# Move "Indécis" to the end, regardless of ranking
candidate_order <- c(
  setdiff(candidate_order, "Indécis"),
  "Indécis"
)

# Set factor levels for ordering
polls_viz <- polls_viz %>%
  mutate(candidat_label = factor(candidat_label, levels = candidate_order))

# Create faceted data: for each facet, mark which candidate is highlighted
polls_faceted <- polls_viz %>%
  # Create a version for each facet
  tidytable::crossing(facet_candidate = unique(polls_viz$candidat_label)) %>%
  mutate(
    is_highlighted = (candidat_label == facet_candidate),
    color = candidate_colors[candidat],
    alpha = ifelse(is_highlighted, 1, 0.2),
    linewidth = ifelse(is_highlighted, 1.2, 0.5)
  )

# Create ribbons only for highlighted candidate in each facet
polls_ribbons <- polls_faceted %>%
  filter(is_highlighted)

# Create the faceted timeline plot ---------------------------------------------
p <- ggplot() +
  # Add margin of error ribbon (only for highlighted candidate)
  geom_ribbon(
    data = polls_ribbons,
    aes(x = date_fin, ymin = lower, ymax = upper, fill = candidat),
    alpha = 0.2,
    show.legend = FALSE
  ) +
  # Add all candidate lines
  geom_line(
    data = polls_faceted,
    aes(x = date_fin, y = vote_pct, color = candidat,
        linewidth = is_highlighted, alpha = is_highlighted, group = candidat),
    show.legend = FALSE
  ) +
  # Add points for each poll
  geom_point(
    data = polls_ribbons,
    aes(x = date_fin, y = vote_pct, color = candidat),
    size = 2.5,
    show.legend = FALSE
  ) +
  # Facet by candidate (using proper names)
  facet_wrap(~ facet_candidate, ncol = 2) +
  # Apply color scales
  scale_color_manual(values = candidate_colors) +
  scale_fill_manual(values = candidate_colors) +
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
    title = "Évolution des intentions de vote - Élection municipale Montréal 2025",
    y = "Intention de vote (%)\n"
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

p

# Save faceted plot ------------------------------------------------------------
ggsave(
  "output/figures/polls_timeline_facet.png",
  plot = p,
  width = 12,
  height = 10,
  dpi = 300,
  bg = "white"
)

cat("\nGraphique avec facets sauvegardé: output/figures/polls_timeline_facet.png\n")


# ==============================================================================
# COMBINED PLOT - All candidates on one graph
# ==============================================================================

# Prepare poll labels for annotations ------------------------------------------
poll_labels <- polls_viz %>%
  distinct(poll_id, poll_firm, date_debut, date_fin) %>%
  mutate(
    # Format dates
    date_range = if_else(
      date_debut == date_fin,
      format(date_fin, "%d %b"),
      paste0(format(date_debut, "%d"), "-", format(date_fin, "%d %b"))
    ),
    # Create label with firm name and dates
    label = paste0(stringr::str_to_title(poll_firm), "\n", date_range),
    # Position at top of plot (will be adjusted with ylim expansion)
    y_pos = NA_real_  # Will use max value from plot
  )

# Calculate y position for labels (at top of expanded plot area)
max_vote <- max(polls_viz$vote_pct, na.rm = TRUE)
poll_labels <- poll_labels %>%
  mutate(y_pos = max_vote * 1.35)  # Position at 135% of max value

p_combined <- ggplot(polls_viz, aes(x = date_fin, y = vote_pct, color = candidat_label)) +
  # Add margin of error ribbons
  geom_ribbon(
    aes(ymin = lower, ymax = upper, fill = candidat_label),
    alpha = 0.15,
    color = NA
  ) +
  # Add lines
  geom_line(linewidth = 1.2) +
  # Add points
  geom_point(size = 3) +
  # Add poll labels at the top
  geom_text(
    data = poll_labels,
    aes(x = date_fin, y = y_pos, label = label),
    inherit.aes = FALSE,
    size = 3.5,
    fontface = "bold",
    color = "grey30",
    lineheight = 0.9,
    angle = 90,
    hjust = 1
  ) +
  # Apply color scales (map candidate_label to candidat colors)
  scale_color_manual(
    values = setNames(candidate_colors, candidate_labels),
    name = NULL
  ) +
  scale_fill_manual(
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
    limits = c(0, max_vote * 1.5),  # Add 50% space at top for labels
    expand = expansion(mult = c(0, 0))
  ) +
  # Labels
  labs(
    title = "Évolution des intentions de vote - Élection municipale Montréal 2025",
    subtitle = "Tous les candidats (avec marges d'erreur du sondage)",
    y = "Intention de vote (%)\n"
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
  "output/figures/polls_timeline_combined.png",
  plot = p_combined,
  width = 12,
  height = 7,
  dpi = 300,
  bg = "white"
)

cat("Graphique combiné sauvegardé: output/figures/polls_timeline_combined.png\n")
