# Third party material

Prism is copyright Soma Labs, Inc. and licensed under the GNU Affero General Public License v3.0 ([LICENSE](LICENSE)). This repository also holds material that others made. It keeps its own terms, listed here.

## NIH article text

The Explore library, `App/Prism/Core/Articles/ExploreLibrary.json`, holds articles adapted from two National Institutes of Health publications:

- NIH News in Health (newsinhealth.nih.gov), 303 articles;
- NIH Research Matters (www.nih.gov/news-events/nih-research-matters), 685 articles.

Their text is a work of the United States federal government and is in the public domain in the United States (17 U.S.C. 105). Each article names its NIH original in the Sources list at the foot of the reader. Soma added two sections to each article, "Easy things to try" and "Keep in mind"; those additions are covered by this repository's license.

NIH has not reviewed or endorsed Prism or these adaptations. Each article says so in its own text: "This is general wellness information adapted from an NIH article, not reviewed or endorsed by NIH. It is not personal medical advice." No NIH images are bundled.

## MuscleMap drawings

The muscle drawings in `Packages/SomaUI/Sources/SomaUI/Components/Readings/MuscleArt/` are vendored from MuscleMap (https://github.com/melihcolpan/MuscleMap). Each Swift file there carries the lines:

```
//  Copyright © 2026 Melih Colpan. All rights reserved.
//  Licensed under the MIT License.
```

The full license is `LICENSE-MuscleMap.txt` in the same folder, and the app shows it in Settings, About, Open source. Soma's changes: the types are renamed with a `MuscleArt` prefix and kept internal; the path data is unchanged.

## Unsplash photographs

Eighteen photographs in `App/Prism/Assets.xcassets` come from Unsplash and are used under the Unsplash License (https://unsplash.com/license). The license asks for no credit. Prism gives one anyway, in the article reader and in Settings, About.

Article covers, `Assets.xcassets/Articles` (credits in `App/Prism/Core/Articles/BundledArticles.swift`):

| Article | Photographer | Unsplash photo |
|---|---|---|
| sleep-regularity | Suhas Hanjar | https://unsplash.com/photos/PgROW5b4Sw0 |
| deep-sleep | Quentin Schulz | https://unsplash.com/photos/7_jpPTmV65E |
| daylight-and-your-body-clock | Hoover Tung | https://unsplash.com/photos/DjlNzHuv_Ck |
| hrv-basics | Ryan Stone | https://unsplash.com/photos/jV2cNlH4e6A |
| alcohol-and-sleep | Denis Sousa | https://unsplash.com/photos/PzZnixZv12U |
| resting-heart-rate-trends | Giana Bleu | https://unsplash.com/photos/fnQ_Zk9TQQg |
| zone-2-training | Viktor Bystrov | https://unsplash.com/photos/Gi0OMNguFaw |
| vo2-max-and-longevity | Alban Rozes | https://unsplash.com/photos/DhGC1dVw0Tg |
| strength-and-lean-mass | Alora Griffiths | https://unsplash.com/photos/hvFrA-iKQd0 |
| caffeine-timing | Dani | https://unsplash.com/photos/ZLqxSzvVr7I |
| protein-and-muscle | Shelley Pauls | https://unsplash.com/photos/t4X660oKiYs |
| breathing-and-stress | Ant Rozetsky | https://unsplash.com/photos/q-DJ9XhKkhA |

Landscapes, `Assets.xcassets/Landscape` (credits in `App/Prism/Features/Settings/Pages/AboutPage.swift`):

| Aspect | Photograph | Photographer | Unsplash photo |
|---|---|---|---|
| Sleep | Half Dome under moon in Yosemite | Casey Horner | https://unsplash.com/photos/mPnxwQBtUZE |
| Mind | Lake reflection | Thomas Grams | https://unsplash.com/photos/1Q578d01zas |
| Body | Sand dunes | raouf bedrani | https://unsplash.com/photos/oVWm9rQpbq0 |
| Heart | Calm water at golden hour | Linus Nylund | https://unsplash.com/photos/JP23z_-dA74 |
| Gut | Valley from a high point | Nils Schirmer | https://unsplash.com/photos/qWmUGrV8B54 |
| Activity | Mountain at sunrise | Mario von Rotz | https://unsplash.com/photos/HHYpIR68Eds |

## Apple symbols and fonts

Prism draws SF Symbols and sets its text in SF Pro, both supplied by Apple's operating systems and not included in this repository. They belong to Apple and are used under Apple's terms. The AGPL does not cover them.

## Swift packages fetched at build time

Swift Package Manager fetches these when you build. They are not part of this repository, and each keeps the license in its own repository: supabase-swift (github.com/supabase/supabase-swift), and its dependencies swift-asn1, swift-crypto and swift-http-types (github.com/apple), and swift-clocks, swift-concurrency-extras, swift-issue-reporting and xctest-dynamic-overlay (github.com/pointfreeco). The exact versions are pinned in `App/Prism.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Soma's marks

Soma, Soma Labs, the Soma mark and the app icons are trademarks of Soma Labs, Inc. and aren't licensed under the AGPL. See [TRADEMARKS.md](TRADEMARKS.md).
