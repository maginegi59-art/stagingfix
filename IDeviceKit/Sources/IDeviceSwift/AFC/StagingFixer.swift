//
//  StagingFixer.swift
//  StagingFix — creates /PublicStaging in the device's AFC area, nothing else.
//
//  *** This file belongs INSIDE the IDeviceSwift module. ***
//  Drop it into a local copy of IDeviceKit at:
//      Sources/IDeviceSwift/AFC/StagingFixer.swift
//  (Feather-style local package, e.g. the "IDeviceKitten" submodule layout.)
//  It must live in the module because HeartbeatManager's RSD adapter /
//  handshake are internal; InstallationProxy.install() uses them the same way.
//
//  What it does, and only this:
//    1. Opens the RSD tunnel with the pairing file in Documents
//       (HeartbeatManager.pairingFile(), same as Feather/SideStore flows).
//    2. Connects to the AFC service over that tunnel.
//    3. Stats "PublicStaging" — if it is already a directory, done.
//    4. If missing, creates it with afc_make_directory and stats again.
//
//  Background: AltStore Classic (installed via AltStore PAL, on-device
//  pairing) fails to install IPAs with IdeviceError Code=106
//  Afc(ObjectNotFound) when /PublicStaging does not exist, because its
//  install path uploads into PublicStaging/<bundle-id> without creating
//  the parent first (AltStore issue #1811). The documented workaround is
//  a one-time `afcclient mkdir /PublicStaging` from a Mac. This file is
//  that workaround, on-device.
//

import Foundation
import IDevice

public enum StagingFixer {
	public enum Outcome: Equatable {
		/// /PublicStaging already existed as a directory.
		case alreadyPresent
		/// /PublicStaging was missing and has been created.
		case created
	}

	public enum FixError: Error, CustomStringConvertible {
		case missingPairingFile
		case tunnelFailed
		case afcConnectFailed
		case mkdirFailed(String)
		case verifyFailed(String)

		public var description: String {
			switch self {
			case .missingPairingFile:
				return "Pairing file not found in Documents (pairingFile.plist). Import it first."
			case .tunnelFailed:
				return "Could not open the RSD tunnel. Is LocalDevVPN connected?"
			case .afcConnectFailed:
				return "Could not connect to the AFC service over the tunnel."
			case .mkdirFailed(let detail):
				return "afc_make_directory failed: \(detail)"
			case .verifyFailed(let detail):
				return "PublicStaging still not usable after mkdir: \(detail)"
			}
		}
	}

	/// The staging directory every IPA installer uploads into first.
	public static let stagingPath = "PublicStaging"

	/// Creates /PublicStaging if needed. Safe to run repeatedly (idempotent).
	/// Must be called off the main thread (the tunnel setup blocks).
	public static func ensurePublicStaging() throws -> Outcome {
		let heartbeat = HeartbeatManager.shared

		guard FileManager.default.fileExists(atPath: HeartbeatManager.pairingFile()) else {
			throw FixError.missingPairingFile
		}

		// iOS 17.4+ path: RSD over the LocalDevVPN loopback tunnel.
		// (StagingFix targets iOS 17.4+; the lockdown/TCP-provider path
		//  used pre-17.4 is intentionally not wired up.)
		guard heartbeat.isRsd else {
			throw FixError.tunnelFailed
		}
		guard heartbeat.ensureRSDTunnel() else {
			throw FixError.tunnelFailed
		}
		guard let adapter = heartbeat.adapter, let handshake = heartbeat.handshake else {
			throw FixError.tunnelFailed
		}

		var afcClient: OpaquePointer?
		guard afc_client_connect_rsd(adapter, handshake, &afcClient) == nil, let afcClient else {
			throw FixError.afcConnectFailed
		}
		defer { afc_client_free(afcClient) }

		if _isDirectory(afcClient, stagingPath) {
			return .alreadyPresent
		}

		let mkdirError = afc_make_directory(afcClient, stagingPath)
		guard mkdirError == nil else {
			let detail = mkdirError?.pointee.message.map { String(cString: $0) } ?? "unknown error"
			if let mkdirError { idevice_error_free(mkdirError) }
			throw FixError.mkdirFailed(detail)
		}

		guard _isDirectory(afcClient, stagingPath) else {
			throw FixError.verifyFailed("get_file_info did not report a directory")
		}
		return .created
	}

	/// True when `path` exists in the AFC area and is a directory.
	private static func _isDirectory(_ afcClient: OpaquePointer, _ path: String) -> Bool {
		var info = AfcFileInfo()
		guard afc_get_file_info(afcClient, path, &info) == nil else {
			return false
		}
		defer { afc_file_info_free(&info) }
		guard let ifmt = info.st_ifmt else { return false }
		return String(cString: ifmt) == "S_IFDIR"
	}
}
