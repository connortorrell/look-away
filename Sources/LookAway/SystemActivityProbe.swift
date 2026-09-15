import AppKit
import CoreAudio
import CoreMediaIO
import LookAwayCore

/// Reads real device use rather than which app happens to be in front.
///
/// The microphone side asks CoreAudio for its list of audio processes and picks
/// out the ones with a live input stream, which gives both "is the mic being
/// captured" and "by whom" in one pass. The camera side asks CoreMediaIO
/// whether any camera is running; that answer is per device rather than per
/// process, so on its own it says nothing about which app is responsible, and
/// the matching rules only ever use it to corroborate an attributed app.
///
/// Neither query records anything or opens a device, so neither one trips the
/// microphone or camera permission prompts.
@MainActor
final class SystemActivityProbe: MeetingActivityProbing {
    func sample() -> MeetingActivity {
        let audio = audioActivity()
        return MeetingActivity(
            capturingBundleIDs: audio.capturing,
            playingBundleIDs: audio.playing,
            isCameraInUse: isAnyCameraRunning()
        )
    }

    // MARK: - Audio

    /// Which apps are capturing audio and which are playing it, in one pass
    /// over the audio processes.
    private func audioActivity() -> (capturing: Set<String>, playing: Set<String>) {
        // `kAudioHardwarePropertyProcessObjectList` arrived in macOS 14.4. On
        // 14.0-14.3 the query fails and there is no per-process reading to be
        // had. The device-level answer says only that *something* is on the
        // microphone, which cannot be pinned on a chosen app, so nothing is
        // reported rather than blaming whichever meeting app happens to be open.
        let processes = audioProcessObjectIDs()
        guard !processes.isEmpty else { return ([], []) }

        var capturing: Set<String> = []
        var playing: Set<String> = []
        for process in processes {
            let isCapturing = flag(process, kAudioProcessPropertyIsRunningInput)
            let isPlaying = flag(process, kAudioProcessPropertyIsRunningOutput)
            guard isCapturing || isPlaying else { continue }
            guard let bundleID = bundleID(of: process) else { continue }
            if isCapturing { capturing.insert(bundleID) }
            if isPlaying { playing.insert(bundleID) }
        }
        return (capturing, playing)
    }

    private func bundleID(of process: AudioObjectID) -> String? {
        if let bundleID = string(process, kAudioProcessPropertyBundleID), !bundleID.isEmpty {
            return bundleID
        }
        // Helpers and XPC services sometimes report no bundle ID of their own.
        return bundleIDOfProcess(owning: process)
    }

    private func audioProcessObjectIDs() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    /// Last resort for a process with no bundle ID of its own: look its PID up
    /// in the running applications.
    private func bundleIDOfProcess(owning object: AudioObjectID) -> String? {
        var address = Self.address(kAudioProcessPropertyPID)
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr, pid > 0
        else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    // MARK: - Camera

    private func isAnyCameraRunning() -> Bool {
        var address = Self.cmioAddress(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return false }

        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices
        ) == noErr else { return false }

        return devices.contains { isRunning($0) }
    }

    private func isRunning(_ device: CMIOObjectID) -> Bool {
        var address = Self.cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var running: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &running) == noErr
        else { return false }
        return running != 0
    }

    // MARK: - Property helpers

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func cmioAddress(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(UInt32(selector)),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = Self.address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
        else { return false }
        return value != 0
    }

    private func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return value as String?
    }
}
