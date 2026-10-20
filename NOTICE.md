# Third party material

Prism is copyright Soma Labs, Inc. and licensed under the GNU Affero General Public License v3.0 ([LICENSE](LICENSE)). This repository also holds material that others made. It keeps its own terms, listed here.

## NIH article text

The Explore library, `App/Prism/Core/Articles/ExploreLibrary.json`, holds articles adapted from two National Institutes of Health publications:

- NIH News in Health (newsinhealth.nih.gov), 303 articles;
- NIH Research Matters (www.nih.gov/news-events/nih-research-matters), 685 articles.

Their text is a work of the United States federal government and is in the public domain in the United States (17 U.S.C. 105). Each article names its NIH original in the Sources list at the foot of the reader. Soma added two sections to each article, "Easy things to try" and "Keep in mind"; those additions are covered by this repository's license.

NIH has not reviewed or endorsed Prism or these adaptations. Each article says so in its own text: "This is general wellness information adapted from an NIH article, not reviewed or endorsed by NIH. It is not personal medical advice." No NIH images are bundled.

## Muscle figure (Z-Anatomy, BodyParts3D)

The muscle figure on Body (muscle freshness) is a set of images in `Packages/SomaUI/Sources/SomaUI/Resources/MuscleFigure/`: the body front and back as light and shade, and one mask per muscle group and side. They are rendered from:

- Z-Anatomy, the libre 3D atlas of anatomy (https://github.com/Z-Anatomy/Models-of-human-anatomy), by Gauthier Kervyn and the Z-Anatomy contributors, licensed under CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/);
- whose muscle meshes come from BodyParts3D, The Database Center for Life Science (https://dbarchive.biosciencedbc.jp/en/bodyparts3d/), licensed under CC BY-SA 2.1 Japan (https://creativecommons.org/licenses/by-sa/2.1/jp/).

Credit line, as the app shows it in Settings, About, Open source:

"Muscle illustrations rendered from Z-Anatomy, the libre 3D atlas of anatomy (CC BY-SA 4.0), based on BodyParts3D, The Database Center for Life Science (CC BY-SA 2.1 Japan). The illustrations are shared under CC BY-SA 4.0."

Share alike applies to the images: they are adaptations, so the files in that folder are shared under CC BY-SA 4.0, not under the AGPL, and anyone may reuse them on those terms. `NOTICE.txt` in the same folder repeats this. Soma's changes: the muscles chosen and lit for a front and a back view, rendered to grey shading with one mask per muscle group. The atlas also bundles an inner ear model (CC BY-NC-SA 4.0) and a kidney model (CC BY-NC 4.0); neither is used. The render script lives in the private Soma_iOS repository (`scripts/muscle-render/`) and is not part of this export.

## Unsplash photographs

Eighteen photographs in `App/Prism/Assets.xcassets` come from Unsplash and are used under the Unsplash License (https://unsplash.com/license). The license asks for no credit. Prism gives one anyway: each of the twelve article covers is credited under the cover, in its article's reader, and the six landscapes in Settings, About. Soma cropped each one to its slot and gave the set one gentle grade (muted colour, soft contrast, lifted blacks, a warm balance); nothing else was changed.

Article covers, `Assets.xcassets/Articles` (credits in `App/Prism/Core/Articles/BundledArticles.swift`):

| Article | Photographer | Unsplash photo |
|---|---|---|
| sleep-regularity | Efe Kekikciler | https://unsplash.com/photos/APy5TV9HrVo |
| deep-sleep | Christopher Farrugia | https://unsplash.com/photos/FqOMlLb5o7Y |
| daylight-and-your-body-clock | Lawless Capture | https://unsplash.com/photos/_-_OBX0mOJI |
| hrv-basics | Kateryna Hliznitsova | https://unsplash.com/photos/biHkVTrULUQ |
| alcohol-and-sleep | Alexey Demidov | https://unsplash.com/photos/HBOL4tVLmCU |
| resting-heart-rate-trends | Alexander Grey | https://unsplash.com/photos/8wcV6KTFdG8 |
| zone-2-training | Tiberiu Popa | https://unsplash.com/photos/9qrMsQDaUXQ |
| vo2-max-and-longevity | Gabriel Francesco | https://unsplash.com/photos/3hD1VIDhIlw |
| strength-and-lean-mass | Rafik Wahba | https://unsplash.com/photos/IFSFaEGoBU8 |
| caffeine-timing | ibmoon Kim | https://unsplash.com/photos/8uJjd2XjoFA |
| protein-and-muscle | Siora Photography | https://unsplash.com/photos/DCOiZhT-WkI |
| breathing-and-stress | Tom Garritty | https://unsplash.com/photos/xJN1Pi7Cy6U |

Landscapes, `Assets.xcassets/Landscape` (credits in `App/Prism/Features/Settings/Pages/AboutPage.swift`):

| Aspect | Photograph | Photographer | Unsplash photo |
|---|---|---|---|
| Sleep | Moss in a pool of light, dark forest | Matthieu Lemarchal | https://unsplash.com/photos/rCgw95aGmVs |
| Mind | Light rays in a mossy redwood forest | Landon Parenteau | https://unsplash.com/photos/D0pMST46enU |
| Body | Warm moss on the forest floor | Erik Mclean | https://unsplash.com/photos/Qk28DEeEKc8 |
| Heart | Sunrise through the trees | Etienne Delorieux | https://unsplash.com/photos/Nmd9UJLoCE4 |
| Gut | Fronds against the dark | Mohamed Elwaid | https://unsplash.com/photos/vcrRGVsivK0 |
| Activity | A ray of sunlight on a mossy path | Sini Tiainen | https://unsplash.com/photos/T2EvkDxqvMY |

## Apple symbols and fonts

Prism draws SF Symbols and sets its text in SF Pro, both supplied by Apple's operating systems and not included in this repository. They belong to Apple and are used under Apple's terms. The AGPL does not cover them.

## Swift packages fetched at build time

Swift Package Manager fetches these when you build. They are not part of this repository, and each keeps the license in its own repository: supabase-swift (github.com/supabase/supabase-swift), and its dependencies swift-asn1, swift-crypto and swift-http-types (github.com/apple), and swift-clocks, swift-concurrency-extras, swift-issue-reporting and xctest-dynamic-overlay (github.com/pointfreeco). The exact versions are pinned in `App/Prism.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Soma's marks

Soma, Soma Labs, the Soma mark and the app icons are trademarks of Soma Labs, Inc. and aren't licensed under the AGPL. See [TRADEMARKS.md](TRADEMARKS.md).
