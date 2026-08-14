import AVFoundation
import CoreMedia
import Foundation

enum CaptureAudio {
    static func makeAACInput() -> AVAssetWriterInput {
        var stereo = AudioChannelLayout()
        stereo.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        let layoutData = Data(bytes: &stereo, count: MemoryLayout<AudioChannelLayout>.size)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
            AVChannelLayoutKey: layoutData,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    /// Dual tracks: never mux system + mic into one `AVAssetWriterInput`.
    static func append(
        _ sampleBuffer: CMSampleBuffer,
        to input: AVAssetWriterInput?,
        pts: CMTime,
        lastPTS: inout CMTime
    ) -> Bool {
        guard let input, input.isReadyForMoreMediaData else { return false }
        let outPTS = CaptureTiming.monotonicPTS(pts, previous: lastPTS)
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: outPTS,
            decodeTimeStamp: .invalid
        )
        var timed: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &timed
        )
        guard let timed else { return false }
        let ok = input.append(timed)
        if ok {
            lastPTS = outPTS
        }
        return ok
    }
}
