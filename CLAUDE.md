# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Substack Election Forecasting - Montreal Municipal Election 2025**

This project develops a hybrid electoral forecasting model for the Montreal municipal election (November 2, 2025). The model combines:
- **Polling data** (intentions de vote)
- **Media coverage analysis** (sentiment, momentum, visibility)

Current timeline: **5 days before election** (as of October 29, 2025)

## Electoral Context (2025)

### Léger Poll Data (Sept 26-30, 2025)
**Methodology**: n=500, online panel (LEO), ±4.4% margin of error, weighted by age/gender/region/education

**Satisfaction with Plante Administration (Projet Montréal)**:
- 37% satisfied (6% very, 32% somewhat)
- 55% dissatisfied (20% somewhat, 35% very)
- Strong dissatisfaction among 55+ (67%), francophones (53%), East (61%)

**Change Appetite**:
- 62% want to change teams
- 16% want to continue with current team
- 22% undecided

**Interest Level**:
- 68% interested (20% very, 48% somewhat)
- 28% not interested
- Higher interest among Martinez Ferrada (84%), Rabouin (67%), Sauvé (84%), Thibodeau (81%) supporters

**Candidate Name Recognition & Favorability**:
| Candidate | Name Recognition | Favorable | Unfavorable | Net Score |
|-----------|------------------|-----------|-------------|-----------|
| Martinez Ferrada | 47% | 32% | 15% | +16 |
| Rabouin | 39% | 19% | 20% | -1 |
| Sauvé | 33% | 19% | 15% | +4 |
| Thibodeau | 25% | 14% | 10% | +4 |
| Kacou | 20% | 9% | 11% | -2 |

**Top Electoral Issues** (% mentioning as top 3):
1. Rental costs/property access (48%)
2. Homelessness/social housing (38%)
3. Traffic congestion/construction (33%)
4. Public transit (27%)
5. Neighborhood safety/crime (21%)
6. Tax levels (19%)
7. Cleanliness/snow removal/services (19%)

**Issue Ownership by Candidate Supporters**:
- Martinez Ferrada voters: taxes (29%), cleanliness (26%), safety (27%), congestion (39%)
- Rabouin voters: public transit (45%), transport actif (17%), housing issues (47%+38%)
- Sauvé voters: housing crisis (63%+63%), climate (20%), public transit (36%)

**Cost of Living Perception**:
- 65% find Montreal unaffordable (40% somewhat, 25% not at all)
- 31% find it affordable
- Rabouin supporters more likely to find it affordable (43% vs 33% overall)

### Key Electoral Dynamics
- **Massive uncertainty**: Léger poll shows deep dissatisfaction but unclear vote distribution
- **Change appetite**: 62% want new leadership vs 16% supporting current team
- **Low baseline turnout**: 38% in 2021, 42.5% in 2017 - turnout modeling critical
- **Name recognition crisis**: Rabouin (61% don't know), Kacou (80%), Thibodeau (75%), Sauvé (67%) unknown
- **Martinez Ferrada advantage**: Only candidate with positive name recognition AND favorable rating

## Data Sources

### Available Documentation
- `doc/contexte_medias.md` - Media articles tracking campaign coverage
- `doc/Elections-municipales-a-Montreal-PostMedia.pdf` - PostMedia analysis
- `doc/revue_litt_elicit.pdf` - Literature review on forecasting methodologies

### Media Sources (see contexte_medias.md)
- Radio-Canada (polling coverage)
- L'actualité (political analysis)
- La Presse (party dynamics)

## Modeling Approach: Parsimonious Hybrid Forecasting

### Literature-Based Best Practices

**Key Research Findings** (from `doc/revue_litt_elicit.pdf`):

1. **Hybrid Models Outperform Polls Alone**:
   - Tsakalidis et al. (2015): Twitter + polls in multivariate time-series beats polls-only models
   - Colladon (2020): Semantic Brand Score from online news achieves 1.6% MAPE for referenda, 19.8% for general elections
   - Jain & Kumar (2017): Social media + news with SVM = 79.4% F-measure

2. **Timing is Critical**:
   - **Peak accuracy 1 week before election** (Colladon 2020)
   - High-frequency data most valuable in final 5-7 days (perfect for our context!)
   - Real-time/near-real-time updates improve accuracy as election approaches

3. **Most Predictive Media Metrics**:
   - **Salience** (volume of coverage) > sentiment alone
   - Semantic Brand Score (network-based importance in news)
   - Momentum (temporal changes in coverage)
   - Combined sentiment + volume features

### Proposed Parsimonious Model

**Model Type**: Bayesian hierarchical model (Stan/PyMC)

**Why Bayesian?**
- Naturally handles uncertainty (critical with 62% wanting change but unclear beneficiary)
- Incorporates prior information from Léger poll
- Provides full probability distributions, not just point estimates
- Can model undecided voter allocation probabilistically

**Core Components** (listed by importance based on literature):

#### 1. Polling Prior (Baseline)
- **Input**: Léger poll (Sept 26-30) as Bayesian prior
- **Adjustment**: Decay weight slightly (now 29 days old, not 5 days)
- **Uncertainty**: Model undecided voters as latent allocation

#### 2. Media Salience Score (Primary Signal)
- **Metric**: Share of total media coverage per candidate (collected every 10 minutes)
- **Why**: Colladon (2020) shows salience outperforms sentiment for elections
- **Calculation**:
  ```
  Salience_i = (Mentions_i / Total_mentions) * (1 + Semantic_importance)
  ```
- **Semantic importance**: Network centrality of candidate in article graph (co-mentions, headline vs body)

#### 3. Media Momentum (Temporal Derivative)
- **Metric**: 7-day rolling change in salience
- **Why**: Captures late-breaking shifts; Jain & Kumar (2017) show momentum predicts final outcome
- **Window**: Compare last 3 days vs previous 4 days (optimal for 5-day horizon)

#### 4. Sentiment Adjustment (Secondary Signal)
- **Metric**: Net sentiment (positive - negative mentions) from news articles
- **Why**: Ceron et al. (2013) show sentiment correlates with surveys; but LESS predictive than salience
- **Method**: Simple lexicon-based (faster than ML, sufficient for French news)
- **Weight**: Lower than salience (literature shows volume > tone)

#### 5. Name Recognition Correction
- **Input**: Poll data showing Rabouin (61% unknown), Kacou (80%), Thibodeau (75%), Sauvé (67%)
- **Why**: Candidates with low name recognition have higher variance; media exposure can shift this
- **Method**: Interact media salience with (1 - recognition_rate) to model "discovery effect"

#### 6. Issue Ownership Matching (Optional Enhancement)
- **Input**: Track which candidate is mentioned with which issues (housing, transit, taxes, etc.)
- **Link**: Match to poll data on issue importance
- **Why**: Candidates "owning" salient issues gain support (Garcia et al. 2018)

**Model Equation** (simplified):

```
Vote_share_i ~ Dirichlet(alpha_i)

alpha_i = poll_prior_i *
          exp(β₁ * salience_i +
              β₂ * momentum_i +
              β₃ * sentiment_i +
              β₄ * recognition_adjustment_i +
              β₅ * issue_match_i)
```

**Parameters to Estimate**:
- β₁: Weight on media salience (expect high, ~0.5-1.0 based on Colladon)
- β₂: Weight on momentum (expect moderate, ~0.3-0.5)
- β₃: Weight on sentiment (expect low, ~0.1-0.2)
- β₄: Recognition adjustment (expect ~0.2-0.4)
- β₅: Issue ownership (expect ~0.1-0.3)

**Parsimony Principle**:
- Start with components 1-3 only (poll + salience + momentum)
- Add 4-5 only if they improve out-of-sample validation
- Keep model simple enough to run in <5 minutes for daily updates

**Example Implementation in R/brms**:

```r
library(brms)
library(tidyverse)

# Prepare data: combine poll prior with media metrics
model_data <- tibble(
  candidate = c("Martinez Ferrada", "Rabouin", "Sauvé", "Thibodeau", "Kacou"),

  # Poll prior (from Léger, normalized to sum to 1 among these 5)
  poll_prior = c(0.40, 0.25, 0.15, 0.12, 0.08),  # example values

  # Media metrics (latest 3 days average)
  salience = c(0.35, 0.28, 0.15, 0.12, 0.10),  # share of media coverage
  momentum = c(0.05, -0.03, 0.02, 0.01, -0.01),  # change in salience
  sentiment = c(0.15, -0.08, 0.10, 0.05, -0.02),  # net sentiment

  # Name recognition (from poll)
  recognition = c(0.47, 0.39, 0.33, 0.25, 0.20)
)

# Dirichlet-Multinomial model with brms
# Log-link to ensure positive concentration parameters
model_formula <- bf(
  poll_prior | weights(1) ~
    1 +  # intercept
    salience +
    momentum +
    sentiment +
    I(salience * (1 - recognition)),  # discovery effect
  family = dirichlet()
)

# Fit model
fit <- brm(
  formula = model_formula,
  data = model_data,
  prior = c(
    prior(normal(0, 1), class = "b", coef = "salience"),
    prior(normal(0, 0.5), class = "b", coef = "momentum"),
    prior(normal(0, 0.3), class = "b", coef = "sentiment")
  ),
  chains = 4,
  iter = 2000,
  warmup = 1000,
  cores = 4,
  backend = "cmdstanr"  # faster than rstan
)

# Extract posterior predictions
post_pred <- posterior_predict(fit, newdata = model_data, ndraws = 4000)

# Calculate win probabilities
win_probs <- model_data %>%
  mutate(
    win_prob = colMeans(apply(post_pred, 1, function(x) x == max(x)))
  )

# Visualize uncertainty
library(tidybayes)
library(ggdist)

post_pred %>%
  as_tibble(.name_repair = ~ model_data$candidate) %>%
  pivot_longer(everything(), names_to = "candidate", values_to = "vote_share") %>%
  ggplot(aes(x = vote_share, y = candidate)) +
  stat_halfeye(.width = c(0.5, 0.9)) +
  geom_vline(xintercept = 0.5, linetype = "dashed", alpha = 0.5) +
  labs(
    title = "Forecasted Vote Share Distribution",
    x = "Vote Share",
    y = "Candidate"
  ) +
  theme_minimal()
```

**Alternative: Simpler Multinomial Logistic Regression**:

```r
library(nnet)

# If Dirichlet too complex, use multinomial logit as baseline
model_data_long <- model_data %>%
  mutate(
    # Transform poll prior to log-odds vs reference (Martinez Ferrada)
    logit_prior = log(poll_prior / poll_prior[1])
  )

# Multinomial logit
fit_multinom <- multinom(
  candidate ~ salience + momentum + sentiment + offset(logit_prior),
  data = model_data_long,
  weights = poll_prior  # weight by poll certainty
)

# Bootstrap for uncertainty
library(boot)
boot_fn <- function(data, indices) {
  fit <- multinom(candidate ~ salience + momentum + offset(logit_prior),
                  data = data[indices, ], weights = poll_prior[indices])
  predict(fit, type = "probs")
}

boot_results <- boot(model_data_long, boot_fn, R = 1000)
```

### Output Format
- **Probability distributions** for each candidate (full posterior)
- **Win probabilities** (P(candidate wins | data))
- **Confidence intervals** (50%, 90%, 95%)
- **Scenario analysis**:
  - High turnout (45%) vs low (35%) - affects incumbent penalty
  - Undecided break proportional vs disproportionate to current leaders
  - Media momentum continues vs stabilizes
- **Forecast trajectory**: Daily updates showing probability evolution
- **Validation metrics**: Compare to final results on Nov 2
- **Publication-ready visualizations** for Substack:
  - Probability time-series (spaghetti plots)
  - Outcome distributions (ridge plots)
  - Scenario comparisons (faceted bar charts)

## Development Guidelines

### Data Pipeline Architecture

**Media Data** (already structured):
- **Format**: Pre-processed time-series data with entity extraction completed
- **Expected variables**:
  - `timestamp`: Date/time of article collection
  - `candidate`: Candidate name (Martinez Ferrada, Rabouin, Sauvé, Thibodeau, Kacou)
  - `party`: Party affiliation
  - `mentions`: Count of mentions in article
  - `salience_score`: Weighted importance metric
  - `sentiment`: Positive/negative/neutral classification (if available)
  - `issue_tags`: Associated issues (housing, transit, taxes, etc.)
  - `source`: Media outlet (Radio-Canada, La Presse, etc.)

**Statistical Processing in R**:
```r
# Aggregate to daily candidate-level metrics
media_daily <- media_raw %>%
  mutate(date = as.Date(timestamp)) %>%
  group_by(date, candidate) %>%
  summarise(
    mentions_total = sum(mentions),
    salience_mean = mean(salience_score),
    salience_total = sum(salience_score),
    sentiment_net = sum(sentiment == "positive") - sum(sentiment == "negative"),
    .groups = "drop"
  ) %>%
  group_by(candidate) %>%
  mutate(
    # Momentum: 3-day vs 4-day rolling average
    salience_recent = slider::slide_mean(salience_total, before = 2, complete = TRUE),
    salience_baseline = slider::slide_mean(salience_total, before = 6, after = -3, complete = TRUE),
    momentum = (salience_recent - salience_baseline) / (salience_baseline + 1)
  )
```

**Polling Data Integration**:
- Parse Léger PDF into structured format (CSV/tibble)
- Variables needed: `candidate`, `favorable_pct`, `unfavorable_pct`, `recognition_pct`, `vote_intention` (if reported)
- If new polls appear: update Bayesian prior, weight by recency (exponential decay)

**Data Quality Checks in R**:
```r
# Check for missing data patterns
media_daily %>%
  group_by(candidate) %>%
  summarise(
    n_days = n(),
    pct_missing = mean(is.na(salience_total)),
    max_gap_days = max(diff(date))
  )

# Flag anomalies (>3 SD from mean)
media_daily %>%
  group_by(candidate) %>%
  mutate(
    z_score = (salience_total - mean(salience_total)) / sd(salience_total),
    anomaly = abs(z_score) > 3
  ) %>%
  filter(anomaly)
```

### Modeling Stack (R-Based)

**Core R Libraries**:
- **brms** for Bayesian modeling (user-friendly Stan interface, recommended) OR **rstan** for direct Stan access
- **tidyverse** (dplyr, tidyr, purrr) for data wrangling
- **data.table** optional for very large datasets (if media archive >1M rows)
- **bayesplot** + **posterior** for MCMC diagnostics and visualization
- **ggplot2** + **patchwork** for publication graphics
- **ggdist** for uncertainty visualizations (ridge plots, intervals)

**Statistical Modeling Packages**:
- **DirichletReg** if using Dirichlet regression approach
- **MCMCpack** alternative lightweight Bayesian toolkit
- **rstanarm** if want pre-compiled models (faster than brms for standard models)

**Forecasting Utilities**:
- **tidybayes** for extracting and manipulating posterior draws
- **modelr** for cross-validation frameworks
- **yardstick** for accuracy metrics (MAPE, RMSE, etc.)

**Model Validation Strategy**:
1. **Temporal cross-validation**:
   - Train on days 1-N, test on day N+1
   - Measure calibration (predicted probabilities vs actual outcomes in training period)
2. **Sensitivity analysis**:
   - Vary β weights ±50%, check forecast stability
   - Test scenarios: momentum doubles, sentiment flips, etc.
3. **Post-election validation** (Nov 2):
   - Calculate final MAPE (Mean Absolute Percentage Error)
   - Compare to baseline (Léger poll alone)
   - Document what worked and what didn't for future elections

### Key Methodological Considerations

**Uncertainty Quantification**:
- **Wide credible intervals justified**: 62% want change but unclear beneficiary
- Report 50% interval (likely range) and 90% interval (plausible range)
- Communicate uncertainty clearly to readers: "Martinez Ferrada has a 60% chance of winning" NOT "Martinez Ferrada will win"

**Temporal Dynamics**:
- Update forecast **daily** (literature shows accuracy improves as election nears)
- Archive each day's forecast for transparency
- Show forecast evolution over time (not just final prediction)

**Computational Efficiency**:
- Target <5 minutes per model run (enables daily updates without stress)
- Use informative priors to reduce MCMC sampling time
- Consider variational inference (ADVI) if MCMC too slow

**Transparency for Substack Readers**:
- Document all assumptions (priors, weights, exclusions)
- Show multiple scenarios, not single "best guess"
- Explain in plain language: "We combined poll data with media coverage patterns..."
- Post-mortem after election: honest assessment of what worked

**Limitations to Acknowledge**:
- Model cannot predict black swan events (scandals, endorsements in final 48h)
- Media salience ≠ voter enthusiasm (silent majority may not generate headlines)
- Municipal elections have weaker polling history than federal/provincial
- Low turnout amplifies uncertainty (who actually shows up?)

## Project Structure

Recommended directory structure (R-based):

```
substack_elxn_mtl/
├── data/
│   ├── raw/
│   │   ├── media/           # Pre-structured media data (CSV/RDS)
│   │   ├── polls/           # Léger PDF and parsed CSV
│   │   └── historical/      # Past election results for validation
│   ├── processed/
│   │   ├── media_daily.rds      # Daily aggregated media metrics
│   │   ├── model_inputs.rds     # Final modeling dataset
│   │   └── poll_priors.csv      # Poll-based priors
│   └── outputs/
│       ├── forecasts/           # Daily forecast archives (RDS)
│       ├── posteriors/          # Saved MCMC draws
│       └── validation/          # Cross-validation results
├── R/
│   ├── 01_data_prep.R           # Process media & poll data
│   ├── 02_feature_engineering.R # Calculate momentum, sentiment aggregation
│   ├── 03_baseline_model.R      # Poll-only baseline
│   ├── 04_hybrid_model.R        # Main Bayesian model (brms/stan)
│   ├── 05_diagnostics.R         # MCMC convergence checks
│   ├── 06_validation.R          # Cross-validation framework
│   ├── 07_visualization.R       # Forecast plots
│   └── utils/
│       ├── model_helpers.R      # Reusable model functions
│       ├── plot_themes.R        # ggplot2 custom themes
│       └── metrics.R            # MAPE, calibration functions
├── analysis/
│   ├── 01_exploratory_analysis.Rmd
│   ├── 02_baseline_forecasts.Rmd
│   ├── 03_hybrid_model_development.Rmd
│   ├── 04_sensitivity_analysis.Rmd
│   └── 05_final_forecast_report.Rmd
├── output/
│   ├── figures/             # Publication-ready plots (PNG/PDF)
│   ├── tables/              # Model summaries (CSV/LaTeX)
│   ├── substack/            # Markdown drafts for Substack
│   └── final_forecast/      # Nov 1 final prediction bundle
├── stan/                    # Optional: custom Stan models
│   ├── dirichlet_hybrid.stan
│   └── multinomial_logit.stan
├── tests/
│   └── testthat/
│       ├── test_data_prep.R
│       ├── test_model_fitting.R
│       └── test_metrics.R
├── doc/                     # Documentation (already exists)
│   ├── CLAUDE.md
│   ├── contexte_medias.md
│   ├── Elections-municipales-a-Montreal-PostMedia.pdf
│   └── revue_litt_elicit.pdf
├── .Rprofile                # Project-specific R settings
├── renv.lock                # Dependency management (optional)
├── substack_elxn_mtl.Rproj  # RStudio project file
└── README.md
```

**Key R Project Setup**:

```r
# .Rprofile
# Automatically load project settings
if (file.exists("renv.lock")) {
  source("renv/activate.R")
}

# Set options
options(
  mc.cores = parallel::detectCores(),  # for Stan/brms parallelization
  brms.backend = "cmdstanr",           # faster Stan backend
  tidyverse.quiet = TRUE
)

# Load common packages
library(tidyverse)
library(here)  # for path management

# Source utilities
source(here("R/utils/model_helpers.R"))
source(here("R/utils/metrics.R"))
```

**Typical R Workflow**:

1. **Data preparation**: `source("R/01_data_prep.R")`
2. **Feature engineering**: `source("R/02_feature_engineering.R")`
3. **Baseline model**: `source("R/03_baseline_model.R")`
4. **Hybrid model**: `source("R/04_hybrid_model.R")`
5. **Diagnostics**: `source("R/05_diagnostics.R")`
6. **Generate forecasts**: `source("R/07_visualization.R")`

Or use RMarkdown for reproducible reporting: `rmarkdown::render("analysis/05_final_forecast_report.Rmd")`

## Key References

### Literature (Electoral Forecasting with Media Data)

1. **Colladon, A. F. (2020)**. "Forecasting Election Results by Studying Brand Importance in Online News." arXiv.
   - **Key finding**: Semantic Brand Score from news achieves 1.6% MAPE for referenda when computed 1 week before election
   - **Relevance**: Directly applicable to our news-based salience approach

2. **Tsakalidis, A. et al. (2015)**. "Predicting Elections for Multiple Countries Using Twitter and Polls." IEEE Intelligent Systems.
   - **Key finding**: Hybrid Twitter + polls outperforms polls-only models
   - **Relevance**: Validates hybrid approach for short-term forecasting

3. **Jain, V. & Kumar, S. (2017)**. "Towards Prediction of Election Outcomes Using Social Media."
   - **Key finding**: Social media + news with SVM = 79.4% F-measure
   - **Relevance**: Shows value of combining multiple media sources

4. **Ceron, A. et al. (2013)**. "Every Tweet Counts? Sentiment Analysis of Social Media." New Media & Society.
   - **Key finding**: Social media sentiment improves correlation with mass surveys
   - **Relevance**: Sentiment as supplementary (not primary) signal

5. **Duval, D. & Pétry, F. (2016)**. "L'analyse Automatisée Du Ton Médiatique." Canadian Journal of Political Science.
   - **Key finding**: French-language lexicon (LSDFr) for automated sentiment analysis
   - **Relevance**: Ready-made tool for Quebec media sentiment

6. **Garcia, A. C. et al. (2018)**. "The PredNews Forecasting Model." Digital Government Research.
   - **Key finding**: News comments for municipal elections achieve high accuracy
   - **Relevance**: Demonstrates feasibility at municipal level

### Practical Considerations

**What Makes This Model Parsimonious**:
- Only 3-5 core parameters to estimate (vs complex ML models with thousands)
- Leverages existing poll as prior (no training from scratch)
- Simple lexicon-based sentiment (no fine-tuning required)
- Focus on salience (easy to measure) over complex semantic analysis
- Fast inference (<5 min) enabling daily updates

**What Makes It Rich in Media Data**:
- High-frequency collection (every 10 minutes) captures real-time dynamics
- Multi-dimensional metrics: volume, momentum, sentiment, co-mentions
- Issue-candidate matching links media to voter priorities
- Temporal resolution allows detection of late-breaking shifts

**Expected Performance**:
- **Best case**: 1-3% MAPE (Colladon 2020 benchmark for referenda)
- **Realistic case**: 5-10% MAPE (municipal elections more volatile than national)
- **Success metric**: Outperform poll-only baseline by >2 percentage points
- **Validation**: Correct winner prediction + narrow confidence intervals

## Next Steps (R-Based Workflow)

### Phase 1: Data Preparation & EDA (Day 1)

**Tasks**:
1. Load pre-structured media data into R
2. Parse Léger poll PDF → tibble with candidate-level metrics
3. Exploratory data analysis:
   - Time-series plots of media salience by candidate
   - Correlation matrix: salience, momentum, sentiment, poll favorability
   - Identify data quality issues (missing values, outliers)

**R Script**: `R/01_data_prep.R`
```r
library(tidyverse)
library(pdftools)
library(here)

# Load media data
media_raw <- read_csv(here("data/raw/media/media_timeseries.csv"))

# Parse poll data from PDF (or manually enter from doc/)
poll_data <- tibble(
  candidate = c("Martinez Ferrada", "Rabouin", "Sauvé", "Thibodeau", "Kacou"),
  favorable_pct = c(32, 19, 19, 14, 9),
  unfavorable_pct = c(15, 20, 15, 10, 11),
  recognition_pct = c(47, 39, 33, 25, 20)
)

write_csv(poll_data, here("data/processed/poll_priors.csv"))
```

**Deliverable**: `analysis/01_exploratory_analysis.Rmd` with key visualizations

---

### Phase 2: Baseline Model (Days 2)

**Tasks**:
1. Implement poll-only baseline (no media data)
2. Bootstrap for uncertainty quantification
3. Calculate baseline forecast metrics

**R Script**: `R/03_baseline_model.R`
```r
# Simple baseline: poll results + uncertainty from sample size
baseline_forecast <- poll_data %>%
  mutate(
    vote_share_mean = favorable_pct / sum(favorable_pct),
    vote_share_se = sqrt(vote_share_mean * (1 - vote_share_mean) / 500),  # n=500
    ci_lower = vote_share_mean - 1.96 * vote_share_se,
    ci_upper = vote_share_mean + 1.96 * vote_share_se
  )
```

**Benchmark**: This is what we need to beat with the hybrid model

---

### Phase 3: Hybrid Model Development (Days 3-4)

**Tasks**:
1. Feature engineering: calculate momentum from media time-series
2. Fit Bayesian hybrid model (brms or Stan)
3. MCMC diagnostics (Rhat, ESS, trace plots)
4. Extract posterior predictions

**R Script**: `R/04_hybrid_model.R`

**Modeling approach**:
- Start simple: `vote_share ~ salience + momentum` only
- Add complexity if justified: `+ sentiment + recognition_interaction`
- Use weakly informative priors (Normal(0, 1) for standardized predictors)
- Compare models with LOO-CV (leave-one-out cross-validation via `loo` package)

**Validation**:
```r
library(loo)

# Compare models
loo_baseline <- loo(fit_baseline)
loo_hybrid <- loo(fit_hybrid)

loo_compare(loo_baseline, loo_hybrid)
# Expected: hybrid model has lower ELPD (better predictive accuracy)
```

**Deliverable**: Fitted model object saved as `data/outputs/posteriors/hybrid_model.rds`

---

### Phase 4: Visualization & Uncertainty Quantification (Day 4-5)

**Tasks**:
1. Generate win probability estimates
2. Create scenario analyses (high/low turnout, momentum scenarios)
3. Produce publication-ready figures for Substack

**R Script**: `R/07_visualization.R`

**Key visualizations**:
```r
library(ggdist)
library(patchwork)

# 1. Posterior vote share distributions
p1 <- posterior_draws %>%
  ggplot(aes(x = vote_share, y = candidate)) +
  stat_halfeye(.width = c(0.5, 0.9), point_interval = "median_qi") +
  labs(title = "Forecasted Vote Share (5 days before election)")

# 2. Win probability bar chart
p2 <- win_probs %>%
  ggplot(aes(x = reorder(candidate, win_prob), y = win_prob)) +
  geom_col(aes(fill = win_prob > 0.5)) +
  coord_flip() +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Win Probability by Candidate")

# 3. Temporal evolution (if running daily updates)
p3 <- forecast_archive %>%
  ggplot(aes(x = date, y = win_prob, color = candidate)) +
  geom_line(linewidth = 1) +
  geom_point() +
  labs(title = "Forecast Evolution (Last 5 Days)")

# Combine
combined_plot <- (p1 | p2) / p3 + plot_layout(heights = c(1, 1))
ggsave(here("output/figures/final_forecast.png"), combined_plot, width = 12, height = 8)
```

**Deliverable**: `output/substack/forecast_article.Rmd` with embedded plots

---

### Phase 5: Final Forecast & Publication (Day 5 - Nov 1)

**Tasks**:
1. Run final model with all available data through Nov 1
2. Generate comprehensive uncertainty report
3. Write Substack article with methodology explainer
4. Archive final forecast for post-election validation

**Key outputs**:
- Point estimates + 50%/90% credible intervals
- Win probabilities
- Scenario table:
  - Base case (current momentum continues)
  - High turnout (45%) vs low (35%)
  - Late momentum shift (+10% salience for trailing candidates)

**Transparency checklist**:
- [ ] Document all priors used
- [ ] Show MCMC diagnostics (convergence achieved)
- [ ] Compare to baseline (poll-only)
- [ ] Acknowledge limitations (can't predict scandals, etc.)
- [ ] Provide data sources and code availability

---

### Phase 6: Post-Election Validation (Nov 2+)

**Tasks**:
1. Compare forecast to actual results
2. Calculate accuracy metrics:
   - MAPE (Mean Absolute Percentage Error)
   - Brier score (calibration of probabilities)
   - Did winner fall within our credible intervals?
3. Write post-mortem analysis for Substack

**R Script**: `R/06_validation.R`
```r
# Load actual results
actual_results <- tibble(
  candidate = c("Martinez Ferrada", "Rabouin", "Sauvé", "Thibodeau", "Kacou"),
  actual_vote_share = c(0.XX, 0.XX, 0.XX, 0.XX, 0.XX)  # fill in after Nov 2
)

# Calculate metrics
validation <- final_forecast %>%
  left_join(actual_results, by = "candidate") %>%
  mutate(
    abs_error = abs(predicted_mean - actual_vote_share),
    in_ci_50 = actual_vote_share >= ci_50_lower & actual_vote_share <= ci_50_upper,
    in_ci_90 = actual_vote_share >= ci_90_lower & actual_vote_share <= ci_90_upper
  )

mape <- mean(validation$abs_error)
calibration_50 <- mean(validation$in_ci_50)  # should be ~0.50
calibration_90 <- mean(validation$in_ci_90)  # should be ~0.90

# Lessons learned document
write_rmd(here("output/substack/post_mortem.Rmd"))
```

**Success criteria**:
- MAPE < 10% (good for municipal election)
- Correct winner predicted with >50% probability
- Credible intervals well-calibrated (actual coverage ≈ nominal coverage)
- Outperform poll-only baseline by ≥2 percentage points
