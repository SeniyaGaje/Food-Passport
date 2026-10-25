# Machine-learning credits

## MobileCLIP-S0

The app bundles Apple's pretrained MobileCLIP-S0 image encoder from
[apple/coreml-mobileclip](https://huggingface.co/apple/coreml-mobileclip), revision
`3e0a7bfb9fe83da8a3efaa3fd8f7df24214bb947`, renamed to
`FoodPassport/ML/MobileCLIPImageEncoder.mlpackage`.

Copyright Apple Inc. Used under the Apple Sample Code License, included in
`FoodPassport/ML/MobileCLIP-LICENSE.txt`.

Pavan Kumar Anasosalu Vasu, Hadi Pouransari, Fartash Faghri, Raviteja Vemulapalli,
and Oncel Tuzel. *MobileCLIP: Fast Image-Text Models through Multi-Modal Reinforced
Training*, CVPR 2024. [Paper](https://arxiv.org/abs/2311.17049).

The frozen encoder is Apple's work. The food-specific classifier is trained with
Create ML Components on the photo dataset documented in this repository.

## Training photos

Photos were discovered through [Wikimedia Commons](https://commons.wikimedia.org/)
and [Openverse](https://openverse.org/). Individual photographs retain their authors'
copyrights and licences. The full attribution ledger is
[`MLTraining/dataset_log.csv`](MLTraining/dataset_log.csv): each entry records the
label, local file, source, title, original page, author, licence, licence URL and SHA-256.
This ledger includes excluded photos; exclusions are listed in
[`MLTraining/excluded.csv`](MLTraining/excluded.csv). Training, validation and test
membership is recorded in [`MLTraining/split.csv`](MLTraining/split.csv).

The collector accepts CC BY, CC BY-SA, CC0 and public-domain photos. No photos from
the app's own illustration catalogue are deliberately included in training.
Original training images are not bundled in the app or tracked in Git.

## App illustrations

See [`PHOTO_CREDITS.md`](PHOTO_CREDITS.md) for the separate credits and licences of
restaurant, meal and welcome-screen illustrations. These remain unseen examples
for testing the classifier.
