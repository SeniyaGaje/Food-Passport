# Food classifier evaluation

Frozen Apple MobileCLIP-S0 image encoder + Create ML Components logistic regression. Only the classifier was trained on these photos.

Split seed: 38. Existing author assignments are preserved when extending the dataset. Authors stay in one split across every class. Only training images have mirrored copies. Validation selects the stopping point and confidence threshold; test photos are used only for final evaluation.

| Split | Original photos | Top-1 accuracy |
|---|---:|---:|
| train | 385 | 100.0% |
| validation | 77 | 88.3% |
| test | 104 | 94.2% |

Training examples with augmentation: 770. Maximum iterations: 500; L2 penalty: 0.01.

## Confidence calibration

Lowest observed validation threshold reaching at least 95% precision with at least five accepted examples: **0.999741**. All results require an explicit choice, including 100% confidence. The threshold is retained for evaluation only.

| Split | Accepted known predictions | Precision | Coverage (all photos) |
|---|---:|---:|---:|
| validation | 24 | 95.8% | 31.2% |
| test | 56 | 100.0% | 53.8% |

## Test precision and recall

| Class | Train | Validation | Test | Precision | Recall |
|---|---:|---:|---:|---:|---:|
| Burger | 22 | 5 | 5 | 100.0% | 100.0% |
| Cake & Dessert | 58 | 6 | 32 | 97.0% | 100.0% |
| Coffee | 23 | 5 | 5 | 60.0% | 60.0% |
| Dosa | 27 | 6 | 6 | 100.0% | 83.3% |
| Fried Rice | 25 | 5 | 6 | 100.0% | 100.0% |
| Hoppers | 27 | 6 | 6 | 85.7% | 100.0% |
| Kottu Roti | 12 | 2 | 3 | 75.0% | 100.0% |
| Other | 105 | 22 | 23 | 100.0% | 100.0% |
| Pizza | 25 | 6 | 5 | 100.0% | 100.0% |
| String Hoppers | 26 | 6 | 6 | 100.0% | 83.3% |
| Tea | 35 | 8 | 7 | 83.3% | 71.4% |

## Test confusion matrix

Rows are actual labels; columns are predicted labels.

| Actual / predicted | Burger | Cake & Dessert | Coffee | Dosa | Fried Rice | Hoppers | Kottu Roti | Other | Pizza | String Hoppers | Tea |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Burger | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Cake & Dessert | 0 | 32 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Coffee | 0 | 1 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| Dosa | 0 | 0 | 0 | 5 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| Fried Rice | 0 | 0 | 0 | 0 | 6 | 0 | 0 | 0 | 0 | 0 | 0 |
| Hoppers | 0 | 0 | 0 | 0 | 0 | 6 | 0 | 0 | 0 | 0 | 0 |
| Kottu Roti | 0 | 0 | 0 | 0 | 0 | 0 | 3 | 0 | 0 | 0 | 0 |
| Other | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 23 | 0 | 0 | 0 |
| Pizza | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 5 | 0 | 0 |
| String Hoppers | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 5 | 0 |
| Tea | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 5 |

## Limits

This is a small web-photo dataset, not a claim of real-world accuracy. A few photos per held-out class give wide uncertainty. Similar dishes, mixed plates, lighting, and unseen drinks can confuse it. Other covers varied everyday scenes and unsupported foods, but cannot cover every unknown image. Confidence is a model score, not a guarantee. Every prediction needs a label confirmation, and every visit needs an explicit Save visit action.

Dropped classes with fewer than ten usable photos: {
    "Rice & Curry" = 8;
}.

## App verification

25 October 2026: all 168 Swift Testing tests passed on the iPhone 18 Pro Simulator. Checks include the real multi-item pipeline on a coffee-and-cake integration fixture, three alternatives per region, independent item choices, no preselection at 100% confidence, saved-photo persistence and account separation, failed-save cleanup, visit deletion/reset, and cancellation on sign-out or reset.

The multi-item fixture is an existing Coffee training image, used to verify integration rather than to measure independent detection accuracy. The model ranks tea above coffee for its cup; coffee is included among the three alternatives and the test explicitly selects it. Whole-image classification accuracy above is separate from object-localisation performance. The four bundled app-photo examples remain excluded from classifier training.

Dataset audit: 566 distinct file hashes and 367 author groups; no author or file hash appears across splits.
