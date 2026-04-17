// Placeholder entry point for the SeshatAppKit executable target.
// Plan 99 (Week 1 Integration) DELETES this file and replaces it with
// Sources/SeshatAppKit/Composition/SeshatAppMain.swift containing
// `@main struct SeshatAppMain: App` wired to AppComposition.
//
// This file exists only so `swift build` can link the executable target
// during Plans 01-04, while still obeying the 'no @main in Sources
// outside Composition/' rule from Plan 04 v2. This is a main.swift
// (SPM-special file), NOT the @main attribute - they are different
// SPM conventions.
import Foundation
exit(0)
