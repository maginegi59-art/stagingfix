//
//  StagingFixApp.swift
//  StagingFix — one-button fix for the missing /PublicStaging directory.
//
//  Minimal SwiftUI shell around StagingFixer (in the IDeviceSwift module).
//  No accounts, no telemetry, no other features.
//

import SwiftUI

@main
struct StagingFixApp: App {
	var body: some Scene {
		WindowGroup {
			ContentView()
		}
	}
}
