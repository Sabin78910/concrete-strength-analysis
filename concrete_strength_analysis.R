# =============================================================================
# Concrete Compressive Strength — Exploratory Data Analysis & Preprocessing
# Author: Sabin Khanal
#
# Pipeline: import -> profile -> missing-value imputation (MICE) ->
#           outlier detection (IQR) -> correlation analysis ->
#           min-max scaling -> principal component analysis (PCA)
# =============================================================================

# ---- 0. Setup ---------------------------------------------------------------
required <- c("mice", "ggplot2", "reshape2")
missing_pkgs <- required[!required %in% rownames(installed.packages())]
if (length(missing_pkgs) > 0) install.packages(missing_pkgs, repos = "https://cloud.r-project.org")

library(mice)
library(ggplot2)
library(reshape2)

set.seed(123)
dir.create("figures", showWarnings = FALSE)

# ---- 1. Data import ---------------------------------------------------------
train_dataset <- read.csv("data/concrete_strength_train.csv", header = TRUE)
test_dataset  <- read.csv("data/concrete_strength_test.csv",  header = TRUE)

# ---- 2. Data profiling ------------------------------------------------------
dim(train_dataset)
dim(test_dataset)
str(train_dataset)
summary(train_dataset)
summary(test_dataset)

# Missing-data patterns
md.pattern(train_dataset, plot = TRUE, rotate.names = TRUE)
md.pattern(test_dataset,  plot = TRUE, rotate.names = TRUE)

# ---- 3. Missing-value handling ----------------------------------------------
# Columns with more than 1% missing values are imputed with MICE using
# predictive mean matching (PMM). Any rows still incomplete are dropped.
clean_missing <- function(df, threshold = 0.01) {
  missing_rate    <- colMeans(is.na(df))
  cols_to_impute  <- names(missing_rate[missing_rate > threshold])
  cols_complete   <- names(missing_rate[missing_rate <= threshold])

  if (length(cols_to_impute) > 0) {
    imputed <- mice(df[, cols_to_impute, drop = FALSE],
                    m = 5, maxit = 50, method = "pmm",
                    seed = 123, printFlag = FALSE)
    imputed <- complete(imputed)
    cleaned <- cbind(imputed, df[, cols_complete, drop = FALSE])
  } else {
    cleaned <- df
  }

  cleaned <- cleaned[, names(df)]          # restore original column order
  cleaned[complete.cases(cleaned), ]
}

cleaned_train_dataset <- clean_missing(train_dataset)
cleaned_test_dataset  <- clean_missing(test_dataset)

summary(cleaned_train_dataset)
summary(cleaned_test_dataset)

# ---- 4. Outlier detection (IQR rule) ----------------------------------------
detect_outliers <- function(df, label) {
  outliers <- list()
  png(sprintf("figures/boxplots_%s.png", label), width = 1200, height = 800)
  par(mfrow = c(3, 3))
  for (col in names(df)) {
    q1  <- quantile(df[[col]], 0.25, na.rm = TRUE)
    q3  <- quantile(df[[col]], 0.75, na.rm = TRUE)
    iqr <- q3 - q1
    idx <- which(df[[col]] < q1 - 1.5 * iqr | df[[col]] > q3 + 1.5 * iqr)
    outliers[[col]] <- idx
    boxplot(df[[col]], main = col, ylab = "Value", col = "lightgray")
  }
  dev.off()
  sapply(outliers, length)                  # outlier count per feature
}

detect_outliers(cleaned_train_dataset, "train")
detect_outliers(cleaned_test_dataset,  "test")

# ---- 5. Correlation / multicollinearity -------------------------------------
cor_matrix <- cor(cleaned_train_dataset)
round(cor_matrix, 2)

cor_plot <- ggplot(melt(cor_matrix), aes(Var1, Var2, fill = value)) +
  geom_tile() +
  geom_text(aes(label = round(value, 2)), size = 3) +
  scale_fill_gradient2(low = "blue", mid = "white", high = "red",
                       limits = c(-1, 1)) +
  theme_minimal() +
  labs(x = "", y = "", fill = "Correlation",
       title = "Feature Correlation Matrix") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave("figures/correlation_heatmap.png", cor_plot, width = 8, height = 6)

# Strength vs age
age_plot <- ggplot(cleaned_train_dataset, aes(Age, Strength)) +
  geom_point(alpha = 0.5) +
  geom_smooth(method = "loess", se = FALSE, colour = "red") +
  theme_minimal() +
  labs(x = "Age (days)", y = "Compressive strength (MPa)",
       title = "Concrete Strength vs Curing Age")
ggsave("figures/strength_vs_age.png", age_plot, width = 8, height = 5)

# ---- 6. Min-max scaling -----------------------------------------------------
# Scaling parameters are learned on the training set only and applied to
# the test set, preventing information leakage from test data.
train_min <- sapply(cleaned_train_dataset, min)
train_max <- sapply(cleaned_train_dataset, max)

scale_with <- function(df, mins, maxs) {
  as.data.frame(Map(function(x, lo, hi) (x - lo) / (hi - lo), df, mins, maxs))
}

training_scaled <- scale_with(cleaned_train_dataset, train_min, train_max)
testing_scaled  <- scale_with(cleaned_test_dataset,  train_min, train_max)

summary(training_scaled)
summary(testing_scaled)

# ---- 7. Principal Component Analysis ----------------------------------------
features <- setdiff(names(training_scaled), "Strength")

pca_result <- prcomp(training_scaled[, features], center = TRUE, scale. = TRUE)
summary(pca_result)
pca_result$rotation                         # component loadings

# Variance explained
var_explained <- data.frame(
  PC = factor(paste0("PC", seq_along(pca_result$sdev)),
              levels = paste0("PC", seq_along(pca_result$sdev))),
  Variance = pca_result$sdev^2 / sum(pca_result$sdev^2)
)
scree_plot <- ggplot(var_explained, aes(PC, Variance)) +
  geom_col(fill = "steelblue") +
  geom_line(aes(group = 1)) +
  geom_point() +
  scale_y_continuous(labels = scales::percent) +
  theme_minimal() +
  labs(title = "PCA — Variance Explained per Component", y = "Variance explained")
ggsave("figures/pca_scree.png", scree_plot, width = 8, height = 5)

# PC1 vs PC2, coloured by strength
scores <- as.data.frame(pca_result$x)
scores$Strength <- cleaned_train_dataset$Strength
pca_plot <- ggplot(scores, aes(PC1, PC2, colour = Strength)) +
  geom_point(alpha = 0.7) +
  scale_colour_viridis_c() +
  theme_minimal() +
  labs(title = "PCA Projection (PC1 vs PC2)", colour = "Strength (MPa)")
ggsave("figures/pca_projection.png", pca_plot, width = 8, height = 6)

# Project the test set onto the training components
test_pca <- predict(pca_result, newdata = testing_scaled[, features])
head(test_pca)
