# Training the food classifier

FoodPassport uses a hybrid model: Apple's frozen **MobileCLIP-S0** image encoder
extracts 512 numbers from a photo. A **logistic regression classifier trained here
with Create ML Components** learns our food labels from those numbers. We train
the classifier, not the MobileCLIP encoder. This is transfer learning, not training
a neural network from scratch.

MobileCLIP is small, works with Core ML on the phone, and describes food images
well enough to train a small classifier without thousands of photos per dish.
The app does not use the text encoder, an external AI service, or Vision scene
prints. It centre-crops the image just as the training script does.

## Files

- `catalogue.json`: the requested foods, drinks, search terms and menu aliases.
- `dataset_log.csv`: every downloaded photo, its hash, source, author and licence.
- `excluded.csv`: obvious bad photos removed during contact-sheet review.
- `split.csv`: the exact train/validation/test assignment and author groups.
- `training_catalogue.json`: classes retained after excluding bad photos.
- `EvaluationReport.md`: measured accuracy, threshold, per-class results and confusion matrix.
- `evaluation_predictions.json`: predictions behind the report, including mistakes.
- `Images/`: original downloaded photos; ignored by Git.

## Steps

Requires a Mac with Xcode and its command-line tools. Python scripts use the
standard library; Swift uses Apple's Core ML, Vision and Create ML Components.
No Python machine-learning packages are needed.

From the project root:

```sh
python3 MLTraining/download_encoder.py
python3 MLTraining/collect_dataset.py --limit 40 --other 150
swift MLTraining/review.swift
python3 MLTraining/exclude.py Images/kottu/example.jpg "Wrong food"
python3 MLTraining/split_dataset.py
swift MLTraining/train_model.swift
```

The collector uses Wikimedia Commons and Openverse, waits between requests,
retries temporary failures and deduplicates file hashes. Add `--ipv4` if the
network has broken IPv6. Use `--labels kottu tea` to collect only selected classes.
It aims for 40 food/drink photos and 150 varied Other photos; some local dishes
have fewer openly licensed examples. Classes with fewer than ten usable photos
are dropped and listed in the report. App illustrations are excluded from the
dataset and tested separately.

`review.swift` makes contact sheets in `Review/`. Remove only obvious unrelated
images, equipment, preparation shots, wrong dishes and duplicate views. Record
each exclusion with `exclude.py`; keep the source ledger intact.

The split is approximately 70/15/15, using seed 38. A photographer stays in one
set across all classes, so related images do not leak into another split.
The exact counts differ where author groups cannot be divided. Training adds
mirrored copies; validation and test photos are never augmented.

Training exports `FoodPassport/ML/FoodClassifier.mlpackage` and `FoodModel.json`.
The JSON includes the lowest observed validation threshold achieving at least
95% precision on five or more accepted known-class predictions. Test precision
is reported separately; it is not used to change the threshold. If no threshold
qualifies, automatic selection is disabled. Other never gets automatically selected.

Above the threshold, the app fills an editable draft item automatically. Low
confidence and Other show three known-class alternatives and require a choice.
Confirming a reviewed result also adds a draft item. The separate Save visit
button is always required to persist the visit.

## Limits and viva explanation

This is a small web-photo dataset, not production accuracy. Similar-looking meals,
mixed plates, dark photos and unseen foods remain difficult. Coffee and tea are
broad labels: the model does not distinguish every drink variation. Small held-out
sets make per-class accuracy uncertain. Other cannot represent every unknown image.
Use the measured report rather than promising a particular accuracy.

Changing the encoder requires retraining the classifier and clearing the embedding
cache. Training photos and intermediate caches are outside the app target.
Sources and licences are credited in the ledger and the root `CREDITS.md`.
