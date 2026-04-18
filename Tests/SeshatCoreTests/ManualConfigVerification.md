## Phase 1 Step 1.6 — Packaged App Base Directory Override

```sh
defaults write com.nitkrar.seshat SeshatBaseDirectoryPath /tmp/seshat-ud-test
open /Applications/Seshat.app
# verify models land under /tmp/seshat-ud-test/models/parakeet-tdt-0.6b-v2/
defaults delete com.nitkrar.seshat SeshatBaseDirectoryPath
```

Record the packaged-app verification outcome here after the user-driven check is complete.
