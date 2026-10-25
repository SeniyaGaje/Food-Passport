# Food classifier evaluation

Frozen Apple MobileCLIP-S0 image encoder + Create ML Components logistic regression. Only the classifier was trained on these photos.

Split seed: 38. Authors stay in one split across every class. Only training images have mirrored copies. Validation selects the stopping point and confidence threshold; test photos are used only for final evaluation.

| Split | Original photos | Top-1 accuracy |
|---|---:|---:|
| train | 316 | 100.0% |
| validation | 68 | 91.2% |
| test | 70 | 92.9% |

Training examples with augmentation: 632. Maximum iterations: 500; L2 penalty: 0.01.

## Confirmation threshold

Lowest observed validation threshold reaching at least 95% precision with at least five accepted examples: **0.827125**. Other is never auto-applied.

| Split | Accepted known predictions | Precision | Coverage (all photos) |
|---|---:|---:|---:|
| validation | 38 | 97.4% | 55.9% |
| test | 44 | 90.9% | 62.9% |

## Test precision and recall

| Class | Train | Validation | Test | Precision | Recall |
|---|---:|---:|---:|---:|---:|
| Burger | 22 | 5 | 5 | 100.0% | 100.0% |
| Coffee | 23 | 5 | 5 | 66.7% | 80.0% |
| Dosa | 27 | 6 | 6 | 100.0% | 83.3% |
| Fried Rice | 25 | 5 | 6 | 100.0% | 100.0% |
| Hoppers | 27 | 6 | 6 | 85.7% | 100.0% |
| Kottu Roti | 12 | 2 | 3 | 75.0% | 100.0% |
| Other | 105 | 22 | 23 | 100.0% | 100.0% |
| Pizza | 25 | 6 | 5 | 100.0% | 100.0% |
| String Hoppers | 26 | 6 | 6 | 100.0% | 83.3% |
| Tea | 24 | 5 | 5 | 75.0% | 60.0% |

## Test confusion matrix

Rows are actual labels; columns are predicted labels.

| Actual / predicted | Burger | Coffee | Dosa | Fried Rice | Hoppers | Kottu Roti | Other | Pizza | String Hoppers | Tea |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Burger | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Coffee | 0 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| Dosa | 0 | 0 | 5 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| Fried Rice | 0 | 0 | 0 | 6 | 0 | 0 | 0 | 0 | 0 | 0 |
| Hoppers | 0 | 0 | 0 | 0 | 6 | 0 | 0 | 0 | 0 | 0 |
| Kottu Roti | 0 | 0 | 0 | 0 | 0 | 3 | 0 | 0 | 0 | 0 |
| Other | 0 | 0 | 0 | 0 | 0 | 0 | 23 | 0 | 0 | 0 |
| Pizza | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 5 | 0 | 0 |
| String Hoppers | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 5 | 0 |
| Tea | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 3 |

## Limits

This is a small web-photo dataset, not a claim of real-world accuracy. A few photos per held-out class give wide uncertainty. Similar dishes, mixed plates, lighting, and unseen drinks can confuse it. Other covers varied everyday scenes and unsupported foods, but cannot cover every unknown image. Confidence is a model score, not a guarantee. Every visit still needs an explicit Save visit action; uncertain predictions also need a label confirmation.

Dropped classes with fewer than ten usable photos: {
    "Rice & Curry" = 8;
}.

## App verification

25 October 2026: the complete Swift Testing suite passed (156 tests, zero failures) on the iPhone 18 Pro Simulator. This includes the exported model interface, catalogue agreement, four unseen bundled app-photo cases, result parsing, threshold boundaries, automatic draft filling, manual confirmation, rejection and a cancelled scan.

The dataset audit also passed: 454 distinct file hashes, 316 author groups, no author or file hash shared across splits, and no excluded photo used for training or evaluation.
