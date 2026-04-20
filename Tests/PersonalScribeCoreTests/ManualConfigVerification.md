## Phase 1 Step 1.6 — Packaged App Base Directory Override

```sh
defaults write com.nitkrar.personal_scribe BaseDirectoryPath /tmp/personal_scribe-ud-test
open /Applications/Ninimma.app
# verify models land under /tmp/personal_scribe-ud-test/models/parakeet-tdt-0.6b-v2/
defaults delete com.nitkrar.personal_scribe BaseDirectoryPath
```

Record the packaged-app verification outcome here after the user-driven check is complete.
