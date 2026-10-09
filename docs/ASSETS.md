# Bundled assets

No destination image is downloaded at runtime. These files are bundled under `ios/App/Assets.xcassets` and usable offline. All photos were fetched 2026-10-03. They depict destinations, not aircraft inventory or bookable services.

| Asset | Source |
| --- | --- |
| Barcelona aerial / Sagrada Família | [Unsplash image source](https://images.unsplash.com/photo-1583422409516-2895a77efded), stored as `barcelona.imageset/photo.jpg` |
| Istanbul / Blue Mosque | [Unsplash image source](https://images.unsplash.com/photo-1541432901042-2d8bd64b4a9b), stored as `istanbul.imageset/photo.jpg` |
| Antalya rocky coast | Alex Jiang, [Unsplash photo page](https://unsplash.com/photos/a-rocky-coast-line-1ytRl3Ubqpc), [image source](https://images.unsplash.com/photo-1657873882134-75e359b54a3b), stored as `antalya.imageset/photo.jpg` |

Photos are from Unsplash; consult the [Unsplash License](https://unsplash.com/license) when redistributing. Meal artwork is original SwiftUI vector illustration in `SeatMealScreens.swift`, intentionally labelled illustrative. Baggage and interface pictograms use system SF Symbols. The app icon is an original yellow direction-arrow mark generated locally. There are no official Pegasus or Apple logos bundled; Apple Pay uses the supported native PassKit button. System typography requires no font downloads. Theme colour is defined in `TripFitApp.swift` and `dashboard/src/styles.css`.

## Design reference

Apple Store's public iPhone screenshots on the [official App Store listing](https://apps.apple.com/us/app/apple-store/id375380948) were visually inspected. They informed the white canvas, system typography, circular category shelf, spacious feature cards and bottom navigation. The supplied Mobbin URL redirected to a public landing page; gated screens were not available. This is an independent Pegasus hackathon prototype, with its own destination content and native booking controls.
