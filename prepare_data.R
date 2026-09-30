# =============================================================================
# prepare_data.R — Download and prepare the Concrete Compressive Strength data
#
# Source: I-Cheng Yeh, "Concrete Compressive Strength" dataset,
#         UCI Machine Learning Repository (1,030 samples, 9 columns).
#
# Output: data/concrete_strength_train.csv  (722 rows)
#         data/concrete_strength_test.csv   (308 rows)
#
# To reflect real-world data quality issues, a small, reproducible share of
# feature values (~4%) is set to missing. The target (Strength) is never
# modified. Set INJECT_MISSING <- FALSE to keep the data complete.
# =============================================================================

INJECT_MISSING <- TRUE
MISSING_RATE   <- 0.04
TRAIN_SIZE     <- 722

if (!"readxl" %in% rownames(installed.packages())) install.packages("readxl", repos = "https://cloud.r-project.org")
library(readxl)

set.seed(123)
dir.create("data", showWarnings = FALSE)

# ---- Download ----------------------------------------------------------------
url      <- "https://archive.ics.uci.edu/static/public/165/concrete+compressive+strength.zip"
zip_path <- file.path(tempdir(), "concrete.zip")
download.file(url, zip_path, mode = "wb")
unzip(zip_path, exdir = tempdir())

xls_file <- list.files(tempdir(), pattern = "Concrete_Data\\.xls$",
                       full.names = TRUE, recursive = TRUE)[1]
concrete <- as.data.frame(read_excel(xls_file))

# ---- Tidy column names --------------------------------------------------------
names(concrete) <- c("Cement", "Blast.Furnace.Slag", "Fly.Ash", "Water",
                     "Superplasticizer", "Coarse.Aggregate", "Fine.Aggregate",
                     "Age", "Strength")
stopifnot(nrow(concrete) == 1030, ncol(concrete) == 9)

# ---- Optional: simulate missing values in the input features -----------------
if (INJECT_MISSING) {
  features <- setdiff(names(concrete), "Strength")
  for (col in features) {
    idx <- sample(nrow(concrete), size = round(MISSING_RATE * nrow(concrete)))
    concrete[idx, col] <- NA
  }
}

# ---- Train / test split --------------------------------------------------------
train_idx <- sample(nrow(concrete), TRAIN_SIZE)
write.csv(concrete[train_idx, ],  "data/concrete_strength_train.csv", row.names = FALSE)
write.csv(concrete[-train_idx, ], "data/concrete_strength_test.csv",  row.names = FALSE)

cat("Saved", TRAIN_SIZE, "training rows and", nrow(concrete) - TRAIN_SIZE,
    "test rows to data/\n")
