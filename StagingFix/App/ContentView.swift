//
//  ContentView.swift
//  StagingFix
//
//  Flow for the user:
//    1. Connect LocalDevVPN.
//    2. Import the pairing file (the .mobiledevicepairing / pairing plist
//       exported from AltStore Classic's on-device pairing, StikPair, etc.).
//       It is copied to Documents/pairingFile.plist, the path IDeviceKit reads.
//    3. Tap "Fix /PublicStaging". The app stats the directory over the
//       loopback AFC service and creates it only if missing, then verifies.
//

import SwiftUI
import UniformTypeIdentifiers
import IDeviceSwift

struct ContentView: View {
	@State private var hasPairingFile = FileManager.default.fileExists(atPath: HeartbeatManager.pairingFile())
	@State private var isImporting = false
	@State private var isWorking = false
	@State private var status: String = "LocalDevVPNをつないでから実行してね。"

	var body: some View {
		VStack(spacing: 20) {
			Image(systemName: "folder.badge.gearshape")
				.font(.system(size: 44))
			Text("/PublicStaging を作るだけのアプリ")
				.font(.headline)
			Text(status)
				.font(.footnote)
				.multilineTextAlignment(.center)
				.foregroundStyle(.secondary)

			Button {
				isImporting = true
			} label: {
				Label(hasPairingFile ? "ペアリングファイルを入れ直す" : "ペアリングファイルを入れる",
				      systemImage: "doc.badge.plus")
			}

			Button {
				runFix()
			} label: {
				if isWorking {
					ProgressView()
				} else {
					Label("PublicStaging を確認して作る", systemImage: "wrench.and.screwdriver")
				}
			}
			.buttonStyle(.borderedProminent)
			.disabled(isWorking || !hasPairingFile)
		}
		.padding()
		.fileImporter(isPresented: $isImporting,
		              allowedContentTypes: [.data, .propertyList]) { result in
			importPairingFile(result)
		}
	}

	private func importPairingFile(_ result: Result<URL, Error>) {
		guard case .success(let src) = result else { return }
		let accessing = src.startAccessingSecurityScopedResource()
		defer { if accessing { src.stopAccessingSecurityScopedResource() } }
		let dest = URL(fileURLWithPath: HeartbeatManager.pairingFile())
		do {
			try? FileManager.default.removeItem(at: dest)
			try FileManager.default.copyItem(at: src, to: dest)
			hasPairingFile = true
			status = "ペアリングファイルを入れた。LocalDevVPN接続後にボタンを押してね。"
		} catch {
			status = "取り込みに失敗: \(error.localizedDescription)"
		}
	}

	private func runFix() {
		isWorking = true
		status = "トンネル経由でAFCに接続中…"
		DispatchQueue.global(qos: .userInitiated).async {
			let result = Result { try StagingFixer.ensurePublicStaging() }
			DispatchQueue.main.async {
				isWorking = false
				switch result {
				case .success(.alreadyPresent):
					status = "✅ /PublicStaging は既にあった。AltStore Classicでインストールを再試行してOK。"
				case .success(.created):
					status = "✅ /PublicStaging を作った。AltStore Classicに戻ってインストールを再試行してね。"
				case .failure(let error):
					status = "⚠️ \((error as? StagingFixer.FixError)?.description ?? error.localizedDescription)"
				}
			}
		}
	}
}

// build re-trigger: run #3 did not start from a README-only push.
// build re-trigger 2: runs #2/#3 both died on GitHub macOS runner capacity.
