# Fictional screenshot fixtures

These images were generated locally for QA. They contain no real booking, passenger identity, account, or ticket. The generator and exact-text/SHA256 manifest document the pixels used in live vision tests.

All dates are October2026; update the generator dates for a future rolling sample window before a presentation. New generated images should retain the FICTIONAL TEST DOCUMENT banner.

Simulator import (replace SIMULATOR_UDID):

```sh
mkdir -p /private/tmp/pegasus-demo-images
cp sample-data/import-fixtures/*-verified.png /private/tmp/pegasus-demo-images/
xcrun simctl addmedia SIMULATOR_UDID /private/tmp/pegasus-demo-images/*-verified.png
```

Copying only these test fixtures to a temporary directory avoids a Simulator bridge hang encountered when importing from macOS's protected Documents directory. Physical devices can use Photos normally. Importing a fixture does not call AI until the passenger taps Extract trip details and confirms the extracted fields.

The two packing-photo test URLs and outcomes are recorded in backend/evidence/live-packing-results.json. Supply your own permitted packing photo for rehearsal; a photo does not establish baggage dimensions or weight.
