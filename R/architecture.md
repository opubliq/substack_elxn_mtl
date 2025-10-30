# R Project Architecture

## Directory Structure

```
R/
├── functions/
│   ├── data_prep.R                 # Load/clean polls & media data
│   ├── data_prep_timeseries.R      # Time series data preparation (daily grid)
│   ├── model_simple.R              # Simple models (multiplicative, bayesian, delta)
│   ├── model_poly_regression.R     # Polynomial regression with time×media interaction
│   ├── model_state_space.R         # Kalman Filter / State-Space model
│   ├── model_bsts.R                # Bayesian Structural Time Series
│   ├── model_var.R                 # Vector Autoregression
│   ├── validation.R                # Validation functions (predict poll_t+4)
│   └── plotting.R                  # Plotting utilities (TBD)
│
├── train_models/
│   ├── 01_train_multiplicative.R   # Simple multiplicative model
│   ├── 02_train_bayesian.R         # Simple Bayesian update model
│   ├── 03_train_delta.R            # Simple delta correction model
│   ├── 04_train_poly_regression.R  # Polynomial regression time series
│   ├── 05_train_state_space.R      # State-Space / Kalman Filter
│   ├── 06_train_bsts.R             # BSTS model
│   └── 07_train_var.R              # VAR model
│
├── 01_prepare_data.R               # Initial data preparation
├── 02_validate_all_models.R        # Run validation for all models on poll_t+4
├── 03_compare_models.R             # Compare metrics (MAPE, AIC, coverage) across models
├── 04_generate_forecast.R          # Final election forecast with best model(s)
├── 05_visualize.R                  # Generate visualizations (strategy TBD)
│
├── TODO.md                          # List of 4 time series models to implement
└── architecture.md                  # This file
```

## Data Flow

```
Raw data (polls.rds, media_salience_daily.csv)
    ↓
01_prepare_data.R → data/processed/model_data.rds
    ↓
train_models/*.R → data/outputs/results_{model_name}.rds
    ↓
02_validate_all_models.R → data/outputs/validation_results_all.rds
    ↓
03_compare_models.R → output/model_comparison.csv
    ↓
04_generate_forecast.R → output/final_forecast.rds
    ↓
05_visualize.R → output/figures/*.png
```

## Validation Strategy

**Single validation target**: Predict poll_t+4 (final poll before election, Oct 25)

**Training data**: Polls 1-3 + media data through poll 3 date

**Rationale**:
- Poll 4 is closest to election (7 days before) → most relevant test
- Minimal but sufficient validation
- No need for dedicated validation folder; functions in `functions/validation.R` are sufficient

**Metrics**:
- MAPE (Mean Absolute Percentage Error)
- MAE (Mean Absolute Error)
- Coverage of prediction intervals (if applicable)
- AIC/BIC for model comparison

## Model Inventory

### Simple Models (existing, kept for comparison)
1. **Multiplicative**: `poll × exp(β·salience)`
2. **Bayesian Update**: Dirichlet prior + pseudo-observations
3. **Delta Correction**: `poll + β·(salience_now - salience_at_poll)`

### Time Series Models (new)
4. **Polynomial Regression**: `vote_t = β₀ + β₁·t + β₂·t² + β₃·salience_t + β₄·(salience×t)`
5. **State-Space (Kalman)**: Latent state with media-driven drift
6. **BSTS**: Bayesian decomposition (trend + regression + seasonal)
7. **VAR**: Multivariate autoregression with cross-candidate effects

**All 7 models will be compared** on the same validation task (predict poll 4).

## Functions Organization

### `functions/data_prep.R`
- `load_polls()`: Load and clean poll data
- `load_media()`: Load media salience data
- `compute_media_features()`: Calculate salience share, momentum, MA7
- `get_media_at_date()`: Extract media metrics at specific date
- `prepare_model_data()`: Combine poll + media for a given poll wave

### `functions/data_prep_timeseries.R` (NEW)
- `create_daily_grid()`: Full date sequence (53 days)
- `interpolate_polls()`: Impute daily vote shares between poll snapshots
- `merge_daily_data()`: Combine interpolated polls + daily media

### `functions/model_*.R`
Each model file exports:
- `fit_{model_name}()`: Train model on data
- `predict_{model_name}()`: Generate predictions with uncertainty
- Model-specific utilities

### `functions/validation.R`
- `validate_on_poll4()`: Predict poll 4 from polls 1-3
- `calculate_metrics()`: Compute MAPE, MAE, coverage
- `compare_models()`: Aggregate metrics across models

### `functions/plotting.R`
- Plotting functions TBD (strategy to be decided collaboratively)
- Will use white backgrounds (`theme_clean()`)

## Outputs

```
data/
├── processed/
│   ├── model_data.rds              # Prepared data (from 01_prepare_data.R)
│   └── daily_timeseries.rds        # Daily grid for time series models
│
└── outputs/
    ├── results_multiplicative.rds
    ├── results_bayesian.rds
    ├── results_delta.rds
    ├── results_poly_regression.rds
    ├── results_state_space.rds
    ├── results_bsts.rds
    ├── results_var.rds
    └── validation_results_all.rds  # Compiled validation metrics

output/
├── model_comparison.csv            # MAPE/MAE/AIC table
├── final_forecast.rds              # Election day forecast
├── final_forecast.csv
└── figures/
    └── *.png                        # Visualizations (TBD)
```

## Design Decisions

### Why separate `train_models/` folder?
- Isolates model-specific training logic
- Each model is self-contained and runnable independently
- Easy to add new models without cluttering root directory

### Why keep simple models?
- Establish baseline performance
- Time series models must beat simple approaches to justify complexity
- Educational: compare static vs. dynamic modeling

### Why single validation point (poll 4)?
- Limited data: only 4 polls available
- Poll 4 is most informative (closest to election)
- Avoids false precision from multiple folds with small N

### Why no dedicated validation folder?
- Single validation task doesn't warrant separate directory
- Validation functions in `functions/validation.R` are sufficient
- Keeps project structure flat and simple

## Workflow

### Development sequence:
1. ✅ Implement simple models (already done)
2. → Implement time series data prep (`data_prep_timeseries.R`)
3. → Implement 4 time series models (one per script in `train_models/`)
4. → Run all models, validate on poll 4 (`02_validate_all_models.R`)
5. → Compare metrics (`03_compare_models.R`)
6. → Generate final forecast (`04_generate_forecast.R`)
7. → Decide visualization strategy and implement (`05_visualize.R`)

### To run entire pipeline:
```r
source("R/01_prepare_data.R")
source("R/train_models/01_train_multiplicative.R")
source("R/train_models/02_train_bayesian.R")
# ... (run all train scripts)
source("R/02_validate_all_models.R")
source("R/03_compare_models.R")
source("R/04_generate_forecast.R")
source("R/05_visualize.R")  # Once viz strategy decided
```

## Notes

- All models predict 6 series: 5 candidates + undecided
- Sum-to-1 constraint enforced at prediction time
- Uncertainty quantification varies by model (intervals vs. posteriors)
- Visualization strategy to be decided collaboratively
